package main

import "core:time"

import rl "vendor:raylib"

GameState :: struct {
	bgm: rl.Music,
	textures: [Textures]rl.Texture,

	camera_pos: [2]f32,
	player_pos: [2]f32,
	player_dir: f32,
	player_anim: string,
	player_state: PlayerState,
	player_anim_frame: int,
	player_anim_timer: int,
	input_dir: [2]f32,
	input_dir_old: [2]f32,
	input_attack: bool,

	monitor_idx: i32,

	entities: []Entity,
	attacks: []Attack,

	last_frame_time: time.Tick,
	fixed_timer: time.Duration,
	fixed_frame: int,

	animation_frames: []AnimFrame,
	next_animation_frame_idx: int,
	animations: map[AnimationId]Animation,
	animation_names: [MAX_ANIMATIONS][MAX_ANIMATION_NAME_LEN]u8,
}

PlayerState :: enum {
	idle,
	move,
	attack,
}

Attacks :: enum {
	none,
	player_sword_horizontal,
	player_sword_up,
	player_sword_down,
}

AttackFlag :: enum {
	rect_hitbox,
}
AttackFlags :: bit_set[AttackFlag]

AttackData :: struct {
	flags: AttackFlags,

	startup: int,
	active: int,
	recovery: int,

	rect: rl.Rectangle,
}

Attack :: struct {
	alive: bool,
	data: Attacks,

	frame: int,
	pos: [2]f32,
	angle: f32,
}

AttackState :: enum { startup, active, recovery }


AnimationId :: struct {
	tex: Textures,
	name: string,
}
Animation :: distinct [2]int

AnimFrame :: struct {
	sheet_rect: rl.Rectangle,
	duration_frames: int,
}