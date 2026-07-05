class_name RoomBuilder
## Layer 3: builds one room's interior from its RoomSpec. Pure function of
## (room_spec, config, world_seed) — doors/open sides are immutable inputs; retries re-roll
## everything else via the attempt index in the seed.
##
## Pipeline per attempt: base FLOOR fill → wall shell with openings erased → organic
## shaping (noise-thickened wall band with per-side asymmetric insets + rounded corners, hashed
## from WORLD tile coords so it is attempt-independent and continuous across collinear walls of
## adjacent rooms) → blob footprint for footprint_blob room types → jittered corridors from every
## opening to the center (all carved tiles PROTECTED) → structure generator → decoration →
## reachability flood fill → validate. After max_room_retries failures the fallback runs
## steps 1–3 only, which validates by construction.
extends RefCounted

# Logical tile classes. Byte values in RoomOutput.tile_grid; PROTECTED is the
# separate parallel mask, never a class value.
const FLOOR := 0
const WALL := 1
const BLOCKER := 2
const DECOR_FLOOR := 3


## Build the interior. `force_fallback` is test-only (exercises the step-8 ladder).
static func build(spec: RoomSpec, config: GenConfig, world_seed: int, force_fallback := false) -> RoomOutput:
	var w := spec.size_slots.x * config.room_slot_tiles
	var h := spec.size_slots.y * config.room_slot_tiles
	var openings := _opening_tiles(spec, w, h)
	if not force_fallback:
		for attempt in config.max_room_retries:
			var out := _attempt(spec, config, world_seed, attempt, true, w, h, openings)
			if _validate(out, openings, config):
				return out
	return _attempt(spec, config, world_seed, config.max_room_retries, false, w, h, openings)


static func _attempt(spec: RoomSpec, config: GenConfig, world_seed: int, attempt: int,
		with_structure: bool, w: int, h: int, openings: PackedInt32Array) -> RoomOutput:
	var rng := config.rng_for([world_seed, WgHash.NS_INTERIOR,
			spec.origin_slot.x, spec.origin_slot.y, attempt] as Array[int])

	var grid := PackedByteArray()
	grid.resize(w * h)               # zero-filled == FLOOR (step 1)
	var prot := PackedByteArray()
	prot.resize(w * h)

	# Step 2 — shell: wall the whole perimeter, then erase (and protect) the openings.
	# World-edge and passage-less sides simply keep their wall.
	for x in w:
		grid[x] = WALL
		grid[(h - 1) * w + x] = WALL
	for y in h:
		grid[y * w] = WALL
		grid[y * w + w - 1] = WALL
	for i in openings.size():
		grid[openings[i]] = FLOOR
		prot[openings[i]] = 1

	# Step 2b — organic shaping: erode the straight shell into a wobbly band and round the
	# corners. Runs before the corridor star, which carves (and protects) its way through.
	_shape_shell(grid, prot, w, h, spec, config, world_seed)

	# Step 2c — blob footprint: the room's usable area becomes an organic pocket; everything
	# outside the noise-warped radius turns WALL, and corridors tunnel through the mass.
	var rt := config.room_type_by_id(spec.type_id)
	if rt != null and rt.footprint_blob:
		_blob_footprint(grid, prot, w, h, spec, config, world_seed)

	# Step 3 — corridor star: every opening connects to the center by a jittered walk.
	var cx := w >> 1
	var cy := h >> 1
	for p in spec.passages:
		_carve_corridor(grid, prot, w, h, p, cx, cy, config.door_width_tiles, rng)

	# Step 4 — structure generator (respects `prot`). A null generator = leave the room empty.
	if with_structure:
		if rt != null and rt.generator != null:
			rt.generator.run(grid, prot, w, h, rng, spec)

		# Step 5 — decoration: non-blocking DECOR_FLOOR at the biome's density;
		# PROTECTED tiles are fair game because decor never blocks. Blocking decor is the
		# structure generators' business. Skipped on the fallback path (steps 1–3 only).
		var biome := config.biome_by_id(spec.biome_id)
		if biome != null and biome.decor_density > 0.0:
			var th := WgHash.threshold(biome.decor_density)
			# rng.randi() < th inlined (== WgHash.chance) — the call overhead dominates
			# this per-tile loop in GDScript.
			for i in grid.size():
				if grid[i] == FLOOR and rng.randi() < th:
					grid[i] = DECOR_FLOOR

	# Step 6 — reachability from center over non-blocking tiles.
	var out := RoomOutput.new()
	out.origin_slot = spec.origin_slot
	out.attempt_used = attempt
	out.width = w
	out.height = h
	out.type_id = spec.type_id
	out.biome_id = spec.biome_id
	out.tile_grid = grid
	out.protected_map = prot
	out.reachability_map = _flood_fill(grid, w, h, cx, cy)

	# Step 7 — population: own RNG, no attempt index — spawn identity survives
	# retries; positions sample this attempt's reachability map. Runs on the fallback too.
	Population.populate(out, spec, config, world_seed, openings)
	return out


## Opening tiles per passage: the erased perimeter tiles, in this room's tile frame.
## OPEN segments are clamped off the side's two corner tiles — a corner belongs to the
## perpendicular wall too, and erasing it would punch a hole in that wall (worst case the
## sealed world edge). Both rooms of an edge apply the same clamp, so they stay consistent.
static func _opening_tiles(spec: RoomSpec, w: int, h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for p in spec.passages:
		var side_len: int = w if (p.side == WorldSpec.SIDE_NORTH or p.side == WorldSpec.SIDE_SOUTH) else h
		var from: int = p.offset_tiles
		var to: int = p.offset_tiles + p.width_tiles
		if p.kind == RoomSpec.KIND_OPEN:
			from = maxi(from, 1)
			to = mini(to, side_len - 1)
		match p.side:
			WorldSpec.SIDE_NORTH:
				for x in range(from, to):
					out.append(x)
			WorldSpec.SIDE_SOUTH:
				for x in range(from, to):
					out.append((h - 1) * w + x)
			WorldSpec.SIDE_WEST:
				for y in range(from, to):
					out.append(y * w)
			WorldSpec.SIDE_EAST:
				for y in range(from, to):
					out.append(y * w + w - 1)
	return out


## Step 2b — organic shell. Each wall is a treeline band: a per-side BASE INSET of
## 0..wall_inset_max tiles (hashed per room side — asymmetric margins, so rooms stop filling
## their slots evenly and the mass between neighbouring rooms varies from thin to fat), plus an
## inner edge thickening inward by 0..wall_extra_depth extra rings of two-octave value noise,
## while the clearing-facing outer edge recedes by 0..wall_outer_erode tiles (occasionally
## gapping the wall entirely) — so no straight grid-aligned wall line survives. Each corner gets
## a quarter-disc of WALL (radius corner_radius ±1). Noise inputs are WORLD tile coordinates
## hashed under NS_WALL_SHAPE — never the attempt index — so the wobble survives retries and
## flows continuously across the collinear walls of adjacent rooms. Protected tiles (openings,
## corridors) are never written. World-boundary sides face the void and never erode (their
## perimeter ring stays sealed).
static func _shape_shell(grid: PackedByteArray, prot: PackedByteArray, w: int, h: int,
		spec: RoomSpec, config: GenConfig, world_seed: int) -> void:
	var depth := mini(config.wall_extra_depth, (mini(w, h) >> 1) - 1)
	var radius := config.corner_radius
	var erode := clampi(config.wall_outer_erode, 0, maxi(mini(w, h) >> 2, 0))
	if depth <= 0 and radius <= 0 and erode <= 0:
		return
	var base := config.seed_for([world_seed, WgHash.NS_WALL_SHAPE] as Array[int])
	var ox := spec.origin_slot.x * config.room_slot_tiles
	var oy := spec.origin_slot.y * config.room_slot_tiles
	var period := maxi(config.wall_noise_period, 1)

	# A side facing the world boundary must stay sealed — no erosion there. The world is a solid
	# biome rectangle (GenConfig.validate), so a side is void-facing iff its edge slot is extremal.
	var wslots_x := config.world_width_biomes * config.biome_slots
	var wslots_y := config.world_height_biomes() * config.biome_slots
	var end := spec.origin_slot + spec.size_slots
	var inset_max := clampi(config.wall_inset_max, 0, mini(w, h) >> 2)
	if depth > 0 or erode > 0 or inset_max > 0:
		# NORTH row 0 / SOUTH row h-1 (inward +y / -y); WEST col 0 / EAST col w-1 (inward +x / -x).
		_shape_side(grid, prot, base, period, depth, erode, _side_inset(base, spec, 0, inset_max),
				w, oy, 0, ox, spec.origin_slot.y == 0, func(i, k): return k * w + i)
		_shape_side(grid, prot, base, period, depth, erode, _side_inset(base, spec, 1, inset_max),
				w, oy + h - 1, 0, ox, end.y == wslots_y, func(i, k): return (h - 1 - k) * w + i)
		_shape_side(grid, prot, base, period, depth, erode, _side_inset(base, spec, 2, inset_max),
				h, ox, 1, oy, spec.origin_slot.x == 0, func(i, k): return i * w + k)
		_shape_side(grid, prot, base, period, depth, erode, _side_inset(base, spec, 3, inset_max),
				h, ox + w - 1, 1, oy, end.x == wslots_x, func(i, k): return i * w + (w - 1 - k))

	if radius > 0:
		_round_corner(grid, prot, w, h, 0, 0, 1, 1, base, ox, oy, radius)
		_round_corner(grid, prot, w, h, w - 1, 0, -1, 1, base, ox + w - 1, oy, radius)
		_round_corner(grid, prot, w, h, 0, h - 1, 1, -1, base, ox, oy + h - 1, radius)
		_round_corner(grid, prot, w, h, w - 1, h - 1, -1, -1, base, ox + w - 1, oy + h - 1, radius)


## Shape one wall of the shell: for each column `i` along it, erode the outer `lo` tiles to FLOOR
## and lay WALL over the band [lo .. hi] inward, where `hi` is the side's base inset plus the
## inner-edge noise depth and `lo` the (decorrelated) outer erosion. `idx_fn(i, k)` maps
## (column, inward depth) → grid index for this side. Erosion is skipped on `void_side` and
## clamped two tiles off each corner, so it can never open the world edge or breach a
## perpendicular wall's shared corner tiles.
static func _shape_side(grid: PackedByteArray, prot: PackedByteArray,
		base: int, period: int, depth: int, erode: int, inset: int, length: int, line: int,
		axis: int, wcoord0: int, void_side: bool, idx_fn: Callable) -> void:
	var er := 0 if void_side else erode
	for i in length:
		var wt := wcoord0 + i
		var hi := inset + (_band_depth(base, axis, line, wt, depth, period) if depth > 0 else 0)
		var lo := 0
		if er > 0 and i >= 2 and i < length - 2:
			lo = _band_depth(base ^ 0x632BE5AB, axis, line, wt, er, period)
		for k in lo:
			var idx: int = idx_fn.call(i, k)
			if prot[idx] == 0:
				grid[idx] = FLOOR
		for k in range(lo, hi + 1):
			var idx2: int = idx_fn.call(i, k)
			if prot[idx2] == 0:
				grid[idx2] = WALL


## Per-side base wall inset in [0, max_inset], hashed from room identity + side index — stable
## across attempts, independent per side, so each room sits asymmetrically inside its slots.
static func _side_inset(base: int, spec: RoomSpec, side: int, max_inset: int) -> int:
	if max_inset <= 0:
		return 0
	var m := WgHash.splitmix64(WgHash.splitmix64(spec.origin_slot.x) ^ WgHash.splitmix64(spec.origin_slot.y))
	m = WgHash.splitmix64(m ^ (side + 0x51ED))
	return posmod(WgHash.splitmix64(base ^ m), max_inset + 1)


## Wall-band depth at position t along a wall line: 1-D value noise summed over TWO octaves —
## a coarse meander (period tiles) plus a half-period octave at a third the weight for bushy,
## ragged edges rather than a smooth sine. Rounded to 0..max_extra. `axis` disambiguates
## horizontal walls (line = world row, t = world column) from vertical ones (transposed).
static func _band_depth(base: int, axis: int, line: int, t: int, max_extra: int, period: int) -> int:
	var coarse := _octave(base, axis, line, t, period)
	var fine := _octave(base ^ 0x9E3779B9, axis, line, t, maxi(period >> 1, 2))
	return int(round((coarse * 0.7 + fine * 0.3) * float(max_extra)))


## One octave of 1-D value noise in [0,1]: lattice samples every `period` tiles, lerped.
static func _octave(base: int, axis: int, line: int, t: int, period: int) -> float:
	var t0 := t - posmod(t, period)
	var f := float(t - t0) / float(period)
	return lerpf(_lattice_val(base, axis, line, t0), _lattice_val(base, axis, line, t0 + period), f)


static func _lattice_val(base: int, axis: int, line: int, t: int) -> float:
	var m := WgHash.splitmix64(WgHash.splitmix64(line) ^ WgHash.splitmix64(t))
	m = WgHash.splitmix64(m ^ axis)
	return float(WgHash.splitmix64(base ^ m) & 0xFFFF) / 65535.0


## Quarter-disc of WALL at room corner (cx0, cy0), growing inward along (sx, sy). The radius
## varies ±1 around base_radius by a hash of the corner's world tile (wx, wy).
static func _round_corner(grid: PackedByteArray, prot: PackedByteArray, w: int, h: int,
		cx0: int, cy0: int, sx: int, sy: int, base: int, wx: int, wy: int, base_radius: int) -> void:
	var m := WgHash.splitmix64(WgHash.splitmix64(wx) ^ WgHash.splitmix64(wy))
	var r := mini(base_radius - 1 + posmod(WgHash.splitmix64(base ^ m), 3), (mini(w, h) >> 1) - 1)
	for j in r:
		var y := cy0 + sy * j
		var row := y * w
		for i in r:
			if i * i + j * j < r * r:
				var idx := row + cx0 + sx * i
				if prot[idx] == 0:
					grid[idx] = WALL


## Blob footprint (step 2c): every unprotected tile whose angle-noised radial distance from the
## room centre exceeds 1 becomes WALL, turning the rectangle into a rounded organic pocket.
## Per-sector radius factors are hashed from room identity — stable across attempts. Openings sit
## on the perimeter, outside the blob; the corridor walk tunnels through the mass to the centre,
## which is exactly the cave-pocket feel (rooms entered through tunnels).
const _BLOB_SECTORS := 16

static func _blob_footprint(grid: PackedByteArray, prot: PackedByteArray, w: int, h: int,
		spec: RoomSpec, config: GenConfig, world_seed: int) -> void:
	var base := config.seed_for([world_seed, WgHash.NS_WALL_SHAPE,
			spec.origin_slot.x, spec.origin_slot.y, 0x6A0B] as Array[int])
	var factors := PackedFloat64Array()
	for s in _BLOB_SECTORS:
		factors.append(0.70 + 0.30 * float(WgHash.splitmix64(base ^ s) & 0xFFFF) / 65535.0)
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	var rx := w * 0.5
	var ry := h * 0.5
	for y in h:
		var row := y * w
		for x in w:
			var idx := row + x
			if prot[idx] == 1:
				continue
			var dx := (x - cx) / rx
			var dy := (y - cy) / ry
			var r := sqrt(dx * dx + dy * dy)
			var fs := (atan2(dy, dx) + PI) * _BLOB_SECTORS / TAU
			var s0 := int(fs) % _BLOB_SECTORS
			var s1 := (s0 + 1) % _BLOB_SECTORS
			if r > lerpf(factors[s0], factors[s1], fs - float(s0)):
				grid[idx] = WALL


## Jittered corridor, width door_width_tiles: a biased random walk of door-width stamps from the
## opening midpoint to the room centre. While within a shell-thickness of the entry wall the walk
## steps straight inward (a sideways stamp there would carve along the shell itself); after that,
## each step moves toward the centre on a randomly chosen pending axis — organic staircases where
## the old L-corridor put a right angle — with occasional perpendicular drift on straight
## stretches. Positions clamp inside the perimeter so stamps never breach another side's wall.
## Consumes the attempt RNG in spec.passages order (deterministic; re-rolled per attempt).
static func _carve_corridor(grid: PackedByteArray, prot: PackedByteArray, w: int, h: int,
		p: RoomSpec.Passage, cx: int, cy: int, door_width: int, rng: RandomNumberGenerator) -> void:
	var mid := p.offset_tiles + (p.width_tiles >> 1)
	var half := door_width >> 1
	var x: int
	var y: int
	match p.side:
		WorldSpec.SIDE_NORTH:
			x = mid
			y = 0
		WorldSpec.SIDE_SOUTH:
			x = mid
			y = h - 1
		WorldSpec.SIDE_WEST:
			x = 0
			y = mid
		_:
			x = w - 1
			y = mid
	var entry_side := p.side
	var straight_depth := half + 2
	var guard := (w + h) * 4
	while (x != cx or y != cy) and guard > 0:
		guard -= 1
		_carve(grid, prot, w, h, x - half, x + half, y - half, y + half)
		var dx := signi(cx - x)
		var dy := signi(cy - y)
		if _wall_distance(entry_side, x, y, w, h) < straight_depth:
			# Still inside the entry wall band: straight inward, no RNG.
			match entry_side:
				WorldSpec.SIDE_NORTH:
					y += 1
				WorldSpec.SIDE_SOUTH:
					y -= 1
				WorldSpec.SIDE_WEST:
					x += 1
				_:
					x -= 1
		elif dx != 0 and dy != 0:
			if rng.randi_range(0, 1) == 0:
				x += dx
			else:
				y += dy
		elif dx != 0:
			x += dx
			if rng.randi_range(0, 3) == 0:
				y += -1 if rng.randi_range(0, 1) == 0 else 1
		else:
			y += dy
			if rng.randi_range(0, 3) == 0:
				x += -1 if rng.randi_range(0, 1) == 0 else 1
		x = clampi(x, half + 1, w - 2 - half)
		y = clampi(y, half + 1, h - 2 - half)
	# Guard expiry (drift kept oscillating): finish with a straight L to the centre.
	if x != cx or y != cy:
		_carve(grid, prot, w, h, mini(x, cx) - half, maxi(x, cx) + half, y - half, y + half)
		_carve(grid, prot, w, h, cx - half, cx + half, mini(y, cy) - half, maxi(y, cy) + half)
	_carve(grid, prot, w, h, cx - half, cx + half, cy - half, cy + half)


## Tiles between (x, y) and the wall the corridor entered through.
static func _wall_distance(side: int, x: int, y: int, w: int, h: int) -> int:
	match side:
		WorldSpec.SIDE_NORTH:
			return y
		WorldSpec.SIDE_SOUTH:
			return h - 1 - y
		WorldSpec.SIDE_WEST:
			return x
		_:
			return w - 1 - x


static func _carve(grid: PackedByteArray, prot: PackedByteArray, w: int, h: int,
		x0: int, x1: int, y0: int, y1: int) -> void:
	x0 = maxi(x0, 0)
	y0 = maxi(y0, 0)
	x1 = mini(x1, w - 1)
	y1 = mini(y1, h - 1)
	for y in range(y0, y1 + 1):
		var row := y * w
		for x in range(x0, x1 + 1):
			grid[row + x] = FLOOR
			prot[row + x] = 1


## 4-connected flood fill over non-blocking tiles (FLOOR, DECOR_FLOOR) from the center.
static func _flood_fill(grid: PackedByteArray, w: int, h: int, cx: int, cy: int) -> PackedByteArray:
	var reach := PackedByteArray()
	reach.resize(w * h)
	var start := cy * w + cx
	if grid[start] == WALL or grid[start] == BLOCKER:
		return reach
	var stack := PackedInt32Array()
	stack.resize(w * h)
	var sp := 0
	stack[sp] = start
	sp += 1
	reach[start] = 1
	while sp > 0:
		sp -= 1
		var idx := stack[sp]
		var x := idx % w
		if x > 0 and reach[idx - 1] == 0 and (grid[idx - 1] == FLOOR or grid[idx - 1] == DECOR_FLOOR):
			reach[idx - 1] = 1
			stack[sp] = idx - 1
			sp += 1
		if x < w - 1 and reach[idx + 1] == 0 and (grid[idx + 1] == FLOOR or grid[idx + 1] == DECOR_FLOOR):
			reach[idx + 1] = 1
			stack[sp] = idx + 1
			sp += 1
		if idx >= w and reach[idx - w] == 0 and (grid[idx - w] == FLOOR or grid[idx - w] == DECOR_FLOOR):
			reach[idx - w] = 1
			stack[sp] = idx - w
			sp += 1
		if idx < (h - 1) * w and reach[idx + w] == 0 and (grid[idx + w] == FLOOR or grid[idx + w] == DECOR_FLOOR):
			reach[idx + w] = 1
			stack[sp] = idx + w
			sp += 1
	return reach


## every opening tile reachable, and reachable tiles ≥ min_reachable_floor_ratio.
static func _validate(out: RoomOutput, openings: PackedInt32Array, config: GenConfig) -> bool:
	for i in openings.size():
		if out.reachability_map[openings[i]] == 0:
			return false
	var total := out.width * out.height
	return out.reachability_map.count(1) >= int(config.min_reachable_floor_ratio * total)
