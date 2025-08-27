package main

import "base:runtime"

import "core:dynlib"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:mem"
import os "core:os/os2"
import "core:time"

import rl "vendor:raylib"

State :: struct {
	should_close: bool,

	exe_dir: string,
	game_state_bytes: []u8,

	lifetime_arena: mem.Arena,
}
Params :: struct {
	init: InitFn,
	deinit: DeinitFn,
	update: UpdateFn,
	render: RenderFn,

	game_state_size: int,
	lifetime_arena_size: int,
}

InitFn :: proc(state: ^State)
DeinitFn :: proc(state: ^State)
UpdateFn :: proc(state: ^State)
RenderFn :: proc(state: ^State)
GetParamsFn :: proc() -> Params

main :: proc() {
	when ODIN_BUILD_MODE != .Executable do return

	rl.InitWindow(WINDOW_SIZE_INITIAL.x, WINDOW_SIZE_INITIAL.y, WINDOW_TITLE)
	rl.InitAudioDevice()

	game_state_bytes: [dynamic]u8
	lifetime_arena_bytes: [dynamic]u8
	params := get_params()
	state: State
	resize(&game_state_bytes, params.game_state_size)
	resize(&lifetime_arena_bytes, params.lifetime_arena_size)
	state.game_state_bytes = game_state_bytes[:]
	mem.arena_init(&state.lifetime_arena, lifetime_arena_bytes[:])

	{
		err: os.Error
		state.exe_dir, err = os.get_executable_directory(context.allocator)
		if err != {} do fmt.panicf("Failed to get executable path!", err)
	}

	when HOT_RELOAD {
		dll: dynlib.Library
		dll_load_time: time.Time
		dll_iteration: int
		dll_path, _ := os.join_path({ state.exe_dir, "bgj.dll" }, allocator = context.allocator)
	}

	{
		context.allocator = mem.panic_allocator()
		params.init(&state)
	}
	for {
		when HOT_RELOAD {
			stat_ok: bool
			stat, stat_err := os.stat(dll_path, context.temp_allocator)
			stat_ok = stat_err == {}

			lib_was_updated := stat_ok && time.diff(dll_load_time, stat.modification_time) > 0
			
			
			copy_path: string
			copy_ok: bool
			if lib_was_updated {
				copy_name := fmt.tprintf("bgj_%v.dll", dll_iteration)
				copy_path, _ = os.join_path({ state.exe_dir, copy_name }, allocator = context.temp_allocator)
				copy_err := os.copy_file(copy_path, dll_path)
				copy_ok = copy_err == {}
			}

			new_lib: dynlib.Library
			new_lib_loaded: bool
			if copy_ok {
				new_lib, new_lib_loaded = dynlib.load_library(copy_path)
			}

			new_get_params: GetParamsFn
			fn_loaded: bool
			if new_lib_loaded {
				p: rawptr
				p, fn_loaded = dynlib.symbol_address(new_lib, "get_params")
				new_get_params = cast(GetParamsFn)p
			}

			if new_lib_loaded && !fn_loaded do dynlib.unload_library(new_lib)

			if fn_loaded {
				new_params := new_get_params()

				game_state_resized := new_params.game_state_size != params.game_state_size
				lifetime_arena_resized := new_params.lifetime_arena_size != params.lifetime_arena_size
				need_full_refresh := game_state_resized || lifetime_arena_resized
				if need_full_refresh {
					params.deinit(&state)

					resize(&game_state_bytes, new_params.game_state_size)
					mem.set(raw_data(game_state_bytes), 0, len(game_state_bytes))

					resize(&lifetime_arena_bytes, new_params.lifetime_arena_size)
					mem.arena_init(&state.lifetime_arena, lifetime_arena_bytes[:])

					state.game_state_bytes = game_state_bytes[:]
					new_params.init(&state)
				}

				params = new_params
				if dll != nil do dynlib.unload_library(dll)
				dll_iteration += 1
				dll_load_time = stat.modification_time
			}
		}

		context.allocator = mem.panic_allocator()
		free_all(context.temp_allocator)
		params.update(&state)
		params.render(&state)

		if state.should_close do break
	}
}

@(export)
get_params :: proc() -> (p: Params) {
	p.init = init
	p.deinit = deinit
	p.update = update
	p.render = render

	p.game_state_size = size_of(GameState)

	anim_map_size: int
	{
		m_info := runtime.map_info(map[AnimationId]Animation)
		m_s := runtime.map_total_allocation_size(MAX_ANIMATIONS, m_info)
		anim_map_size = int(m_s)
	}
	p.lifetime_arena_size = size_of(Entity) * MAX_ENTITIES + size_of(Attack) * MAX_ATTACKS + size_of(AnimFrame) * MAX_ANIMATION_FRAMES + anim_map_size + 64 + MAP_GRID_WIDTH * MAP_GRID_HEIGHT * size_of(MapGridTile)

	return
}

Textures :: enum {
	none,
	checkers,
	player,
	beet_root_scythe,
	beet_root_sword,
	dungeon,
}

TextureLoadInfo :: struct {
	has_spritesheet: bool,
	load_from_data: bool,
	data: []u8,
	filetype: string,
	offset: [2]f32,
	spritesheet_data: []u8,
	spritesheet_loaded: bool,
}


init :: proc(state: ^State) {
	gs := cast(^GameState)raw_data(state.game_state_bytes)
	gs.bgm = rl.LoadMusicStreamFromMemory(".mp3", raw_data(BGM), i32(len(BGM)))
	rl.PlayMusicStream(gs.bgm)

	{
		bg_img := rl.GenImageChecked(CHECK_TEXTURE_SIZE, CHECK_TEXTURE_SIZE, CHECK_GRID_SIZE, CHECK_GRID_SIZE, rl.GRAY, rl.RAYWHITE)
		defer rl.UnloadImage(bg_img)

		gs.textures[.checkers] = rl.LoadTextureFromImage(bg_img)
	}



	{
		current_monitor := rl.GetCurrentMonitor()
		rl.SetTargetFPS(rl.GetMonitorRefreshRate(current_monitor))
		gs.monitor_idx = current_monitor
	}

	lifetime_arena := mem.arena_allocator(&state.lifetime_arena)
	gs.entities = make([]Entity, MAX_ENTITIES, allocator=lifetime_arena)
	gs.animation_frames = make([]AnimFrame, MAX_ANIMATION_FRAMES, allocator=lifetime_arena)
	gs.attacks = make([]Attack, MAX_ATTACKS, allocator=lifetime_arena)
	gs.animations = make(map[AnimationId]Animation, MAX_ANIMATIONS, allocator=lifetime_arena)

	gs.map_grid = make([]MapGridTile, MAP_GRID_WIDTH * MAP_GRID_HEIGHT, allocator=lifetime_arena)

	for &tex, id in gs.textures {
		info := texture_load_db[id]
		if info.load_from_data {
			img := rl.LoadImageFromMemory(fmt.ctprint(info.filetype), raw_data(info.data), i32(len(info.data)))
			tex = rl.LoadTextureFromImage(img)
			rl.UnloadImage(img)
		}

		if info.has_spritesheet {
			load_animation_spritesheet(gs, id)
		}
	}

	gs.player_pos = PLAYER_SPAWN

	gs.last_frame_time = time.tick_now()
}

deinit :: proc(state: ^State) {
	gs := cast(^GameState)raw_data(state.game_state_bytes)
	rl.UnloadMusicStream(gs.bgm)
	for tex in gs.textures do rl.UnloadTexture(tex)
}

update :: proc(state: ^State) {
	gs := cast(^GameState)raw_data(state.game_state_bytes)
	{
		current_monitor := rl.GetCurrentMonitor()
		if current_monitor != gs.monitor_idx do rl.SetTargetFPS(rl.GetMonitorRefreshRate(current_monitor))
		gs.monitor_idx = current_monitor
	}

	gs.input_dir = {}
	if rl.IsKeyDown(.RIGHT) do gs.input_dir.x += 1
	if rl.IsKeyDown(.LEFT) do gs.input_dir.x -= 1
	if rl.IsKeyDown(.UP) do gs.input_dir.y -= 1
	if rl.IsKeyDown(.DOWN) do gs.input_dir.y += 1

	if rl.IsKeyPressed(.SPACE) do gs.input_attack = true

	for gs.fixed_timer >= FIXED_FRAME_DURATION {
		fixed_update(state)
		gs.fixed_timer -= FIXED_FRAME_DURATION
	}

	gs.camera_pos = gs.player_pos

	//rl.UpdateMusicStream(gs.bgm)

	state.should_close = rl.WindowShouldClose()
	gs.fixed_timer += time.tick_lap_time(&gs.last_frame_time)
}

fixed_update :: proc(state: ^State) {
	gs := cast(^GameState)raw_data(state.game_state_bytes)
	gs.fixed_frame += 1
	
	if gs.input_dir != {} && gs.player_state != .attack {
		gs.player_pos += linalg.normalize(gs.input_dir) * PLAYER_SPEED	
		gs.player_dir = math.atan2(-gs.input_dir.y, gs.input_dir.x)
	}

	if gs.player_state == .idle && gs.input_dir != {} do gs.player_state = .move
	if gs.player_state == .move && gs.input_dir == {} do gs.player_state = .idle

	// NOTE: Maybe reset animation frame to 0 when changing animations? But idunno if it even matters.

	gs.player_anim_timer += 1

	anim := get_player_anim(gs^)

	for gs.player_anim_timer > gs.animation_frames[anim[0] + gs.player_anim_frame].duration_frames {
		gs.player_anim_timer -= gs.animation_frames[anim[0] + gs.player_anim_frame].duration_frames
		gs.player_anim_frame += 1
	}

	anim_complete: bool
	if anim[0] == anim[1] {
		gs.player_anim_frame = 0
	} else {
		anim_complete = gs.player_anim_frame >= anim[1] - anim[0]
		gs.player_anim_frame %= anim[1] - anim[0]
	}

	if gs.player_state == .attack && anim_complete {
		gs.player_state = .idle
		gs.player_anim_frame = 0
		gs.player_anim_timer = 0
	}


	gs.input_dir_old = gs.input_dir

	{
		tile, _ := get_tile_from_pos(gs, gs.player_pos)
		tile.has_player_frame = gs.fixed_frame
	}

	gs.alive_entities = 0
	gs.entity_collision_checks = 0

	have_spawned: bool
	for &entity, i in gs.entities {
		if .alive not_in entity.flags {
			if !have_spawned && gs.enemies_spawned < 1024 {
				entity = {
					flags = { .alive },
					texture = .beet_root_sword,
					pos = rand.choice(enemy_spawns),
				}
				have_spawned = true
				gs.enemies_spawned += 1
				gs.enemies_spawned = 0
				gs.alive_entities += 1
			}

			continue
		}
		gs.alive_entities += 1

		tile, coord := get_tile_from_pos(gs, entity.pos)

		seek: [2]f32
		{
			displacement := gs.player_pos - entity.pos
			magnitude := math.sqrt(displacement.x * displacement.x + displacement.y * displacement.y)
			norm: [2]f32
			if magnitude != 0 do norm = displacement / magnitude
			seek = norm
		}

		separate: [2]f32
		for search_y := coord.y - ENEMY_SEPARATION_SEARCH_RANGE; search_y <= coord.y + ENEMY_SEPARATION_SEARCH_RANGE; search_y += 1 {
			if search_y < 0 || search_y >= MAP_GRID_HEIGHT do continue
			for search_x := coord.x - ENEMY_SEPARATION_SEARCH_RANGE; search_x <= coord.x + ENEMY_SEPARATION_SEARCH_RANGE; search_x += 1 {
				if search_x < 0 || search_x >= MAP_GRID_WIDTH do continue
				search_tile := get_tile_from_coord(gs, { search_x, search_y })
				if search_tile.has_entity_frame != gs.fixed_frame do continue

				other := gs.entities[search_tile.entity_idx]
				for {
					gs.entity_collision_checks += 1

					displacement := other.pos - entity.pos
					magnitude := linalg.length(displacement)
					if magnitude >= ENEMY_MIN_SEPARATION {

					} else if magnitude == 0 {
						separate += linalg.matrix2_rotate_f32(rand.float32() * math.PI * 2) * [2]f32{ ENEMY_MIN_SEPARATION, 0 }
					} else {
						repel := displacement / -magnitude
						separate += repel * 10
					}

					if other.next_entity_in_sector.gen != gs.fixed_frame do break
					other = gs.entities[other.next_entity_in_sector.idx]
				}
			}
		}


		vel := linalg.normalize(seek + separate) * ENEMY_SPEED
		entity.pos += vel

		coord = get_coord_from_pos(entity.pos)
		if  !is_tile_walkable(coord) {
			entity.pos -= vel
		}

		tile, _ = get_tile_from_pos(gs, entity.pos)
		if tile.has_entity_frame == gs.fixed_frame {
			other := &gs.entities[tile.entity_idx]
			for other.next_entity_in_sector.gen == gs.fixed_frame {
				other = &gs.entities[other.next_entity_in_sector.idx]
			}
			other.next_entity_in_sector = {
				gen = gs.fixed_frame,
				idx = i,
			}
		} else {
			tile.has_entity_frame = gs.fixed_frame
			tile.entity_idx = i
		}
	}

	spawn_player_sword_strike := gs.input_attack
	for &attack in gs.attacks {


		data := attack_db[attack.data]
		if attack.alive {
			rect := get_attack_rect(attack)
			state := get_attack_state(attack)
			for &entity in gs.entities {
				if state != .active do break
				if rl.CheckCollisionCircleRec(entity.pos, 8, rect) {
					entity.flags -= { .alive }
				}
			}

			attack.frame += 1
			if attack.frame >= data.startup + data.active + data.recovery {
				attack.alive = false
			}
		}

		if !attack.alive && spawn_player_sword_strike && gs.player_state != .attack {
			gs.player_anim_frame = 0
			gs.player_anim_timer = 0
			gs.player_state = .attack
			attack = { 
				alive = true,
				pos = gs.player_pos,
				angle = gs.player_dir,
			}

			p_dir := gs.player_dir
			if p_dir == math.PI * 0.5 || p_dir == -math.PI * 3.5 {
				attack.data = .player_sword_up
			} else if p_dir == -math.PI * 0.5 || p_dir == math.PI * 3.5 {
				attack.data = .player_sword_down
			} else {
				attack.data = .player_sword_horizontal
			}
			spawn_player_sword_strike = false
		}
	}

	gs.input_attack = false

}

render :: proc(state: ^State) {
	gs := cast(^GameState)raw_data(state.game_state_bytes)
	screen_size: [2]f32 = { f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()) }
	
	rl.BeginDrawing()
	defer rl.EndDrawing()


	rl.ClearBackground(rl.BLACK)

	{
		rl.BeginMode2D({
			offset = { screen_size.x * 0.5, screen_size.y * 0.5 },
			target = gs.camera_pos,
			zoom = VIEW_SCALE,
		})
		defer rl.EndMode2D()

		rl.DrawTexture(gs.textures[.dungeon], 0, 0, rl.WHITE)

		for y := 0; y < MAP_GRID_HEIGHT; y += 1 {
			y_pos: i32 = i32(y) * MAP_GRID_SIZE
			for x := 0; x < MAP_GRID_WIDTH; x += 1 {
				x_pos: i32 = i32(x) * MAP_GRID_SIZE

				if is_tile_walkable({x, y}) {
					rl.DrawRectangleLines(x_pos, y_pos, MAP_GRID_SIZE, MAP_GRID_SIZE, rl.BLUE)	
				} else {
					
				}
			}
		}

		for entity in gs.entities {
			if .alive not_in entity.flags do continue

			tex := gs.textures[entity.texture]
			rect: rl.Rectangle = {
				width = f32(tex.width),
				height = f32(tex.height),
			}
			rl.DrawTextureRec(tex, rect, entity.pos - texture_load_db[entity.texture].offset, rl.WHITE)
		}

		{
			crosshair_pos: [2]f32 = gs.player_pos + { CROSSHAIR_DIST, 0 } * linalg.matrix2_rotate(gs.player_dir)
			rl.DrawCircleV(crosshair_pos, CROSSHAIR_RADIUS, CROSSHAIR_COLOR)
		}

		{
			tex := gs.textures[.player]
			tex_db := texture_load_db[.player]

			anim := get_player_anim(gs^)
			assert(anim[0] + gs.player_anim_frame <= anim[1])
			frame := gs.animation_frames[anim[0] + gs.player_anim_frame]
			src_rect := frame.sheet_rect

			player_rect: rl.Rectangle = {
				x = gs.player_pos.x,
				y = gs.player_pos.y,
				width = frame.sheet_rect.width,
				height = frame.sheet_rect.height,
			}
			facing_left := abs(gs.player_dir) > math.PI / 2 && abs(gs.player_dir) < math.PI * 3.5
			if facing_left do src_rect.width *= -1

			rl.DrawTexturePro(tex, src_rect, player_rect, tex_db.offset, 0, rl.WHITE)
		}

		attack_colors: [AttackState]rl.Color = {
			.startup = rl.Fade(rl.YELLOW, 0.4),
			.active = rl.Fade(rl.RED, 0.4),
			.recovery = rl.Fade(rl.BLUE, 0.4),
		}
		for attack in gs.attacks {
			if !attack.alive do continue

			rect := get_attack_rect(attack)
			rl.DrawRectangleRec(rect, attack_colors[get_attack_state(attack)])
		}

	}


	rl.DrawFPS(20, 20)

	avg_collision_checks: int
	if gs.alive_entities > 0 do avg_collision_checks = gs.entity_collision_checks / gs.alive_entities
	debug_txt := fmt.ctprint(gs.alive_entities, avg_collision_checks, gs.entity_collision_checks)
	rl.DrawText(debug_txt, 20, 40, 20, rl.RED)

}

get_player_anim :: proc(#by_ptr gs: GameState) -> Animation {
	switch gs.player_state {
	case .idle: 	return gs.animations[{ tex = .player, name = "Idle" }]
	case .move:
		name := "Run Right"
		if gs.player_dir == math.PI / 2 do name = "Run Up"
		if gs.player_dir == -math.PI / 2 do name = "Run Down"
		return gs.animations[{ tex = .player, name = name }]
	case .attack:	
		name := "Attack Right"
		if gs.player_dir == math.PI / 2 do name = "Attack Up"
		if gs.player_dir == -math.PI / 2 do name = "Attack Down"
		if gs.player_dir == math.PI do name = "Attack Left"
		return gs.animations[{ tex = .player, name = name }]
	}
	return {}
}

get_attack_rect :: proc(atk: Attack) -> (rect: rl.Rectangle) {
	facing_left := abs(atk.angle) > math.PI * 0.5 && abs(atk.angle) < math.PI * 3.5
	data := attack_db[atk.data]
	rect = data.rect
	if facing_left {
		rect.x *= -1
		rect.x -= rect.width
	}
	rect.x += atk.pos.x
	rect.y += atk.pos.y
	return
}

get_attack_state :: proc(atk: Attack) -> AttackState {
	data := attack_db[atk.data]

	if atk.frame < data.startup {
		return .startup
	}

	if atk.frame < data.startup + data.active do return .active

	return .recovery
}

load_animation_spritesheet :: proc(gs: ^GameState, tex: Textures) {
	js, err := json.parse(texture_load_db[tex].spritesheet_data, allocator=context.temp_allocator)
	assert(err == {})

	root := js.(json.Object)

	frames := root["frames"].(json.Array)
	tags := (root["meta"].(json.Object))["frameTags"].(json.Array)

	first_frame := gs.next_animation_frame_idx	
	assert(first_frame + len(frames) < MAX_ANIMATION_FRAMES)
	assert(len(gs.animations) + len(tags) < MAX_ANIMATIONS)

	for tag in tags {
		anim_idx := len(gs.animations)
		tag := tag.(json.Object)
		name := tag["name"].(string)
		assert(len(name) <= MAX_ANIMATION_NAME_LEN)
		name_len := copy(gs.animation_names[anim_idx][:], name)
		name = string(gs.animation_names[anim_idx][:name_len])
		from := tag["from"].(f64)
		to := tag["to"].(f64)
		gs.animations[{tex = tex, name = name}] = { int(from) + first_frame, int(to) + first_frame }
	}

	for frame, i in frames {
		frame := frame.(json.Object)
		duration: int = int(frame["duration"].(f64) / 16.6)
		rect: rl.Rectangle
		fr := frame["frame"].(json.Object)
		rect.x = cast(f32)fr["x"].(f64)
		rect.y = cast(f32)fr["y"].(f64)
		rect.width = cast(f32)fr["w"].(f64)
		rect.height = cast(f32)fr["h"].(f64)

		gs.animation_frames[i + first_frame] = {
			sheet_rect = rect,
			duration_frames = duration,
		}
	}
}

get_tile_from_pos :: proc(gs: ^GameState, pos: [2]f32) -> (tile: ^MapGridTile, coord: [2]int) {
	coord.x = int(pos.x) / MAP_GRID_SIZE
	assert(coord.x < MAP_GRID_WIDTH)
	coord.y = int(pos.y) / MAP_GRID_SIZE
	assert(coord.y < MAP_GRID_HEIGHT)
	idx := coord.y * MAP_GRID_WIDTH + coord.x
	assert(idx < len(gs.map_grid))
	tile = &gs.map_grid[coord.y * MAP_GRID_WIDTH + coord.x]

	return
}

get_tile_from_coord :: proc(gs: ^GameState, coord: [2]int) -> (tile: ^MapGridTile) {
	assert(coord.x < MAP_GRID_WIDTH)
	assert(coord.y < MAP_GRID_HEIGHT)
	idx := coord.y * MAP_GRID_WIDTH + coord.x
	assert(idx < len(gs.map_grid))
	tile = &gs.map_grid[coord.y * MAP_GRID_WIDTH + coord.x]
	return
}

get_coord_from_pos :: proc(pos: [2]f32) -> (coord: [2]int) {
	coord.x = int(pos.x) / MAP_GRID_SIZE
	coord.y = int(pos.y) / MAP_GRID_SIZE
	return
}

is_tile_walkable :: proc(coord: [2]int) -> bool {
	if coord.y < 12 do return false
	return coord.x >= 0 && coord.x < MAP_GRID_WIDTH && coord.y >= 0 && coord.y < MAP_GRID_HEIGHT
}
