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
MAX_ENTITIES :: 1024

PLAYER_SPEED :: 2

texture_load_db := #partial [Textures]TextureLoadInfo {
	.player = {
		has_spritesheet = true,
		load_from_data = true,
		data = #load("player.png"),
		spritesheet_data = #load("player.json"),
		filetype = ".png",
		offset = { 64, 64 },
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
		startup = 20,
		active = 15,
		recovery = 10,
		
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