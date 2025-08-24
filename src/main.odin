package main

import rl "vendor:raylib"

main :: proc() {
	rl.InitWindow(640, 480, "Brackeys Jam Game")
	rl.SetTargetFPS(60)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)

		rl.EndDrawing()	
	}
}

