class_name RoomGenArena
## Arena generator (spec §8.2): a perimeter ring of blockers with gaps, open center — for
## boss/challenge rooms. Gap positions are drawn first (fixed RNG count), then the band is
## filled deterministically.
extends RoomGenBase


func run(grid: PackedByteArray, protected: PackedByteArray, w: int, h: int,
		rng: RandomNumberGenerator, spec: RoomSpec, config: GenConfig) -> void:
	var rt := config.room_type_by_id(spec.type_id)
	var params: ArenaParams = null
	if rt != null:
		params = rt.generator_params as ArenaParams
	var inset := params.inset if params != null else 8
	var thickness := params.thickness if params != null else 2
	var gap_count := params.gap_count if params != null else 4
	var gap_width := params.gap_width if params != null else 4

	# Gaps: (side, offset along that side). Drawn before any placement so the RNG stream is
	# independent of grid contents.
	var gaps: Array[Vector2i] = []
	for _g in gap_count:
		var side := rng.randi_range(0, 3)
		var side_len := w if (side == WorldSpec.SIDE_NORTH or side == WorldSpec.SIDE_SOUTH) else h
		var off := rng.randi_range(inset + 1, maxi(inset + 1, side_len - inset - gap_width - 1))
		gaps.append(Vector2i(side, off))

	var band_lo := inset
	var band_hi := inset + thickness   # exclusive
	for y in range(1, h - 1):
		var row := y * w
		for x in range(1, w - 1):
			var depth := mini(mini(x, w - 1 - x), mini(y, h - 1 - y))
			if depth < band_lo or depth >= band_hi:
				continue
			if _in_gap(gaps, x, y, w, h, band_hi, gap_width):
				continue
			var idx := row + x
			if grid[idx] == RoomBuilder.FLOOR and protected[idx] == 0:
				grid[idx] = RoomBuilder.BLOCKER


static func _in_gap(gaps: Array[Vector2i], x: int, y: int, w: int, h: int,
		band_hi: int, gap_width: int) -> bool:
	for g in gaps:
		match g.x:
			WorldSpec.SIDE_NORTH:
				if y < band_hi and x >= g.y and x < g.y + gap_width:
					return true
			WorldSpec.SIDE_SOUTH:
				if y >= h - band_hi and x >= g.y and x < g.y + gap_width:
					return true
			WorldSpec.SIDE_WEST:
				if x < band_hi and y >= g.y and y < g.y + gap_width:
					return true
			WorldSpec.SIDE_EAST:
				if x >= w - band_hi and y >= g.y and y < g.y + gap_width:
					return true
	return false
