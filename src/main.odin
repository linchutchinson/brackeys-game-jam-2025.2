package main

import "core:fmt"

import rl "vendor:raylib"

import "aseprite"

ASE_FILE :: #load("Sword.aseprite")

main :: proc() {
	rl.InitWindow(640, 480, "Brackeys Jam Game")
	rl.SetTargetFPS(60)

	ase_file := aseprite.parse_bytes(ASE_FILE)

	frame_idx: int
	chunk_idx: int

	for !rl.WindowShouldClose() {
		free_all(context.temp_allocator)

		

		if rl.IsKeyPressed(.UP) {
			frame_idx = min(frame_idx + 1, len(ase_file.frames) - 1)
			chunk_idx = 0
		}

		if rl.IsKeyPressed(.DOWN) {
			frame_idx = max(frame_idx - 1, 0)
			chunk_idx = 0
		}

		frame := ase_file.frames[frame_idx]

		if rl.IsKeyPressed(.RIGHT) {
			chunk_idx = min(chunk_idx + 1, int(frame.chunks) - 1)
		}

		if rl.IsKeyPressed(.LEFT) {
			chunk_idx = max(chunk_idx - 1, 0)
		}

		chunk := aseprite.get_chunk(ase_file, frame_idx, chunk_idx, allocator=context.temp_allocator)

		txt := fmt.ctprint(frame_idx, chunk_idx)

		chunk_txt := fmt.ctprint(chunk.type)

		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)
		rl.DrawText(txt, 20, 20, 20, rl.GRAY)
		rl.DrawText(chunk_txt, 20, 40, 20, rl.GRAY)

		#partial switch chunk.type {
		case .color_profile:
			profile_txt := fmt.ctprint(chunk.color_profile_type, chunk.color_profile_flags, chunk.fixed_gamma, chunk.icc_profile_data)
			rl.DrawText(profile_txt, 20, 60, 20, rl.GRAY)
		case .palette:
			is_hovering: bool
			hover_text: cstring
			mouse_pos := rl.GetMousePosition()

			palette_top_left: [2]f32 = { 80, 80 }
			palette_tile_size: [2]f32 = { 16, 16 }
			palette_tile_gap: [2]f32 = { 4, 4 }

			PALLETTE_COLUMNS :: 5
			for i := 0; i < int(chunk.palette_size); i += 1 {
				y := i / PALLETTE_COLUMNS
				x := i % PALLETTE_COLUMNS
				rect: rl.Rectangle = { 
					x = palette_top_left.x + (palette_tile_size.x + palette_tile_gap.x) * f32(x),
					y = palette_top_left.y + (palette_tile_size.y + palette_tile_gap.y) * f32(y),
					width = palette_tile_size.x, height = palette_tile_size.y,
				}

				if i >= cast(int)chunk.from && i <= cast(int)chunk.to {
					entry := chunk.palette_entries[i - int(chunk.from)]
					col := cast(rl.Color)entry.color
					rl.DrawRectangleRec(rect, col)

					if rl.CheckCollisionPointRec(mouse_pos, rect) {
						is_hovering = true
						hover_text = fmt.ctprint(col)
					}
				}


				rl.DrawRectangleLinesEx(rect, 2, rl.DARKGRAY)
			}

			if is_hovering {
				width := rl.MeasureText(hover_text, 20)
				rect: rl.Rectangle = { x = mouse_pos.x + 8, y = mouse_pos.y, width = f32(width), height = 20 }
				rl.DrawRectangleRec(rect, rl.Fade(rl.BLACK, 0.6))
				rl.DrawText(hover_text, i32(mouse_pos.x) + 8, i32(mouse_pos.y), 20, rl.RAYWHITE)
			}
		case .tags:
			for i := 0; i < len(chunk.tags); i += 1 {
				tag := chunk.tags[i]
				y := i32(80 + i * 20)
				t := fmt.ctprintf("%v: %v-%v %v %v", tag.name, tag.from, tag.to, tag.loop_direction, tag.repeat)
				rl.DrawText(t, 60, y, 20, rl.GRAY)
			}
		case .user_data:
			if .has_text in chunk.user_data_flags {
				t := fmt.ctprint(chunk.user_data_text)
				rl.DrawText(t, 60, 80, 20, rl.GRAY)
			}

			if .has_color in chunk.user_data_flags {
				rl.DrawRectangle(60, 70, 20, 8, cast(rl.Color)chunk.user_data_color)
			}

			if .has_properties in chunk.user_data_flags do assert(false, "Gotta implement this")
		}

		rl.EndDrawing()
	}
}

