package aseprite

parse_bytes :: proc(bytes: []u8, allocator := context.allocator) -> (file: AsepriteFile) {
	if len(bytes) < size_of(Header) do return

	file.bytes = bytes
	file.header = cast(^Header)raw_data(bytes)
	if cast(int)file.header.file_size != len(bytes) do return
	if file.header.magic_number != HEADER_MAGIC_NUMBER do return

	file.frames = make([]^FrameHeader, file.header.frames, allocator=allocator)
	if len(file.frames) != cast(int)file.header.frames do return
	defer if !file.is_valid do delete(file.frames, allocator=allocator)

	idx: u16 = 0
	offset := size_of(Header)
	assert(offset == 128)
	for ; idx < file.header.frames; idx += 1 {
		if offset >= len(bytes) do return

		header := cast(^FrameHeader)&bytes[offset]
		if header.magic_number != FRAME_MAGIC_NUMBER do return

		offset += cast(int)header.size
		file.frames[idx] = header
	}
	if offset < len(bytes) do return

	file.is_valid = true
	return
}

get_chunk :: proc(f: AsepriteFile, frame_idx: int, chunk_idx: int, allocator := context.allocator) -> (chunk: Chunk) {
	if !f.is_valid do return
	if frame_idx > len(f.frames) do return
	if chunk_idx > cast(int)f.frames[frame_idx].chunks do return

	context.allocator = allocator

	frame := f.frames[frame_idx]
	frame_offset := uintptr(frame) - uintptr(raw_data(f.bytes))

	chunk_offset := frame_offset + size_of(FrameHeader)
	for i := 0; i < chunk_idx; i += 1 {
		chunk_header := cast(^ChunkHeader)&f.bytes[chunk_offset]
		chunk_offset += cast(uintptr)chunk_header.size
	}
	chunk.header = cast(^ChunkHeader)&f.bytes[chunk_offset]
	chunk.type = chunk.header.type

	contents := f.bytes[chunk_offset + size_of(ChunkHeader):chunk_offset + uintptr(chunk.header.size)]

	#partial switch chunk.type {
	case .color_profile:
		chunk.color_profile_type = slice_to_type(ColorProfileType, contents[:2])
		chunk.color_profile_flags = slice_to_type(ColorProfileFlags, contents[2:4])
		chunk.fixed_gamma = slice_to_type(f32, contents[4:8])

		if chunk.color_profile_type == .embedded_icc {
			icc_profile_len := slice_to_type(u32, contents[16:20])
			chunk.icc_profile_data = contents[20:20 + int(icc_profile_len)]
		}
	case .palette:
		chunk.palette_size = slice_to_type(u32, contents[:4])
		chunk.from = slice_to_type(u32, contents[4:8])
		chunk.to = slice_to_type(u32, contents[8:12])
		chunk.palette_entries = make([]PaletteEntry, chunk.to - chunk.from + 1)

		offset := 20
		for i := chunk.from; i <= chunk.to; i += 1 {
			entry := &chunk.palette_entries[i]
			entry.has_name =  slice_to_type(u16, contents[offset:offset + 2]) != 0
			entry.color = slice_to_type([4]u8, contents[offset + 2:offset + 6])

			offset += 6

			if entry.has_name {
				len := slice_to_type(u16, contents[offset:offset + 2])
				entry.name = string(contents[offset + 2:offset + 2 + int(len)])
				offset += 2 + int(len)
			}
		}
	case .tags:
		chunk.tags = make([]Tag, slice_to_type(u16, contents[:2]))
		offset := 10

		for i := 0; i < len(chunk.tags); i += 1 {
			tag := &chunk.tags[i]
			tag.from = slice_to_type(u16, contents[offset:offset + 2])
			tag.to = slice_to_type(u16, contents[offset + 2:offset + 4])
			tag.loop_direction = slice_to_type(LoopAnimationDirection, contents[offset + 4: offset + 5])
			tag.repeat = slice_to_type(u16, contents[offset + 5:offset + 7])

			offset += 17
			name_len := slice_to_type(u16, contents[offset:offset + 2])
			tag.name = string(contents[offset + 2:offset + 2 + int(name_len)])
			offset += 2 + int(name_len)
		}
	case .user_data:
		chunk.user_data_flags = slice_to_type(UserDataFlags, contents[:4])

		offset := 4
		if .has_text in chunk.user_data_flags {
			len := slice_to_type(u16, contents[offset:offset + 2])
			chunk.user_data_text = string(contents[offset + 2:offset + 2 + int(len)])
			offset += 2 + int(len)
		}
	}

	return
}

slice_to_type :: proc($T: typeid, slice: []u8) -> T {
	assert(len(slice) == size_of(T))

	return (cast(^T)(raw_data(slice)))^
}

AsepriteFile :: struct {
	is_valid: bool,
	bytes: []u8,
	header: ^Header,
	frames: []^FrameHeader,
}

HEADER_MAGIC_NUMBER :: 0xA5E0
FRAME_MAGIC_NUMBER :: 0xF1FA

HeaderFlag :: enum u32 {
	layer_opacity_valid = 1,
	layer_blend_valid_for_groups = 2,
	layers_have_uuid = 4,
}
HeaderFlags :: bit_set[HeaderFlag; u32]

Header :: struct #packed {
	file_size: u32,
	magic_number: u16,
	frames: u16,
	canvas_x: u16,
	canvas_y: u16,
	color_depth: u16,
	flags: HeaderFlags,
	speed: u16,
	pad_0: u32,
	pad_1: u32,
	palette_transparent_idx: u8,
	pad_2: [3]u8,
	color_count: u16,
	pixel_x: u8,
	pixel_y: u8,
	grid_pos_x: i16,
	grid_pos_y: i16,
	grid_size_x: u16,
	grid_size_y: u16,
	pad_3: [84]u8,
}

FrameHeader :: struct #packed {
	size: u32,
	magic_number: u16,
	chunks_old: u16,
	duration_ms: u16,
	pad: [2]u8,
	chunks: u32,
}

ChunkHeader :: struct #packed {
	size: u32,
	type: ChunkType,
}

ChunkType :: enum u16 {
	invalid 		= 0x0000,
	palette_old_0 	= 0x0004,
	palette_old_1 	= 0x0011,
	layer 			= 0x2004,
	cel 			= 0x2005,
	cel_extra 		= 0x2006,
	color_profile 	= 0x2007,
	external_files 	= 0x2008,
	mask_DEPRECATED = 0x2016,
	path 			= 0x2017,
	tags 			= 0x2018,
	palette 		= 0x2019,
	user_data 		= 0x2020,
	slice 			= 0x2022,
	tileset 		= 0x2023,
}

CelChunkHeader :: struct #packed {
	layer_index: u16,
	pos: [2]i16,
	opacity: u8,
	type: enum u16 { raw_image, linked, compressed_img, compressed_tilemap },
	z_idx: i16,
	pad: [5]u8,
}

Chunk :: struct {
	header: ^ChunkHeader,
	type: ChunkType,

	from: u32,
	to: u32,

	tags: []Tag,

	// Color Profile Chunk
	color_profile_type: ColorProfileType,
	color_profile_flags: ColorProfileFlags,
	fixed_gamma: f32,
	icc_profile_data: []u8,

	// Palette Chunk
	palette_size: u32,
	palette_entries: []PaletteEntry,

	// User Data Chunk
	user_data_flags: UserDataFlags,
	user_data_text: string,
	user_data_color: [4]u8,
	user_data_properties: map[string]UserDataProperty,
}

UserDataProperty :: union {}

UserDataFlag :: enum u32 {
	has_text = 1,
	has_color = 2,
	has_properties = 4,
}

UserDataFlags :: bit_set[UserDataFlag; u32]

Tag :: struct {
	from: u16,
	to: u16,
	loop_direction: LoopAnimationDirection,
	repeat: u16,
	name: string,
}

LoopAnimationDirection :: enum u8 {
	forward = 0,
	reverse = 1,
	ping_pong = 2,
	ping_pong_reverse = 3,
}

PaletteEntry :: struct {
	has_name: bool,
	color: [4]u8,
	name: string,
}

ColorProfileFlag :: enum u16 { use_special_fixed_gamma = 1 }
ColorProfileFlags :: bit_set[ColorProfileFlag; u16]

ColorProfileType :: enum u16 { 
	no_profile = 0,
	srgb = 1,
	embedded_icc = 2,
}
