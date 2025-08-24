package main

import "core:dynlib"
import "core:fmt"
import "core:mem"
import os "core:os/os2"
import "core:time"

import rl "vendor:raylib"

HOT_RELOAD :: #config(HOT_RELOAD, ODIN_DEBUG && ODIN_OS == .Windows)

State :: struct {
	should_close: bool,

	exe_dir: string,
	game_state_bytes: []u8,
}
Params :: struct {
	init: InitFn,
	deinit: DeinitFn,
	update: UpdateFn,
	render: RenderFn,

	game_state_size: int,
}

InitFn :: proc(state: ^State)
DeinitFn :: proc(state: ^State)
UpdateFn :: proc(state: ^State)
RenderFn :: proc(state: ^State)
GetParamsFn :: proc() -> Params

WINDOW_TITLE :: "Brakeys Jam 2025.2 Game"
WINDOW_SIZE_INITIAL : [2]i32 : { 1280, 720 }

main :: proc() {
	when ODIN_BUILD_MODE != .Executable do return

	rl.InitWindow(WINDOW_SIZE_INITIAL.x, WINDOW_SIZE_INITIAL.y, WINDOW_TITLE)

	game_state_bytes: [dynamic]u8
	params := get_params()
	state: State
	resize(&game_state_bytes, params.game_state_size)
	state.game_state_bytes = game_state_bytes[:]

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
				if new_params.game_state_size != params.game_state_size {
					params.deinit(&state)
					clear(&game_state_bytes)
					resize(&game_state_bytes, new_params.game_state_size)
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

	return
}

GameState :: struct {}

init :: proc(state: ^State) {}
deinit :: proc(state: ^State) {}
update :: proc(state: ^State) {
	state.should_close = rl.WindowShouldClose()
}
render :: proc(state: ^State) {
	rl.BeginDrawing()
	rl.ClearBackground(rl.ORANGE)
	rl.EndDrawing()
}

