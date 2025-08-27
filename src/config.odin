package main

import "core:time"

import rl "vendor:raylib"

HOT_RELOAD :: #config(HOT_RELOAD, ODIN_DEBUG && ODIN_OS == .Windows)

WINDOW_TITLE :: "Brakeys Jam 2025.2 Game"
WINDOW_SIZE_INITIAL : [2]i32 : { 1280, 720 }

FIXED_FRAMERATE :: 60
FIXED_FRAME_DURATION :: time.Second / FIXED_FRAMERATE

BGM :: #load("snippet.mp3")

CHECK_TEXTURE_SIZE :: 256
CHECK_GRID_SIZE :: 64

VIEW_SCALE :: 2

CROSSHAIR_DIST :: 32
CROSSHAIR_RADIUS :: 4
CROSSHAIR_COLOR : rl.Color : rl.RED

PLAYER_SHADOW_RADIUS :: 4

MAX_ATTACKS :: 1024
MAX_ENTITIES :: 4096

PLAYER_SPEED :: 2
PLAYER_SPAWN : [2]f32 : { 960, 540 }

MAP_GRID_SIZE :: 16
MAP_GRID_WIDTH :: 120
MAP_GRID_HEIGHT :: 68

@(rodata)
enemy_spawns : [][2]f32 = {
	{ 200, 480 },
	{ 1320, 1015 },
}
ENEMY_SPEED :: 0.5

ENEMY_MIN_SEPARATION :: 16
ENEMY_SEPARATION_SEARCH_RANGE :: (ENEMY_MIN_SEPARATION + MAP_GRID_SIZE - 1) / MAP_GRID_SIZE

texture_load_db := #partial [Textures]TextureLoadInfo {
	.player = {
		has_spritesheet = true,
		load_from_data = true,
		data = #load("player.png"),
		spritesheet_data = #load("player.json"),
		filetype = ".png",
		offset = { 64, 64 },
	},
	.dungeon = {
		load_from_data = true,
		data = #load("dungeon.png"),
		filetype = ".png",
	},
	.beet_root_scythe = {
		load_from_data = true,
		data = #load("beet_root_scythe.png"),
		filetype = ".png",
		offset = { 32, 32 },
	},
	.beet_root_sword = {
		load_from_data = true,
		data = #load("beet_root_sword.png"),
		filetype = ".png",
		offset = { 32, 32 },
	},
}

attack_db := #partial [Attacks]AttackData {
	.player_sword_horizontal = {
		startup = 15,
		active = 15,
		recovery = 15,
		
		rect = { x = 8, y = -32, width = 64, height = 48 },
	},
	.player_sword_up = {
		startup = 0,
		active = 15,
		recovery = 10,
		
		rect = { x = -24, y = -64, width = 48, height = 64 },
	},
	.player_sword_down = {
		startup = 0,
		active = 15,
		recovery = 10,
		
		rect = { x = -24, y = 0, width = 48, height = 64 },
	},
}

MAX_ANIMATIONS :: 64
MAX_ANIMATION_FRAMES :: 1024
MAX_ANIMATION_NAME_LEN :: 32