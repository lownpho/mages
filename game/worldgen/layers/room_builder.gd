class_name RoomBuilder
## Layer 3: builds one room's interior from its RoomSpec. Pure function of
## (room_spec, config, world_seed) — doors/open sides are immutable inputs. Single attempt,
## no retry ladder: correctness is restored afterward by a deterministic, RNG-free repair pass
## rather than by re-rolling.
##
## Pipeline: base FLOOR fill → wall shell with openings erased → organic shaping
## (noise-thickened wall band with per-side asymmetric insets + rounded corners, hashed from
## WORLD tile coords so it is continuous across collinear walls of adjacent rooms; void-facing
## sides — spec.void_sides — never erode) → blob footprint for footprint_blob room types →
## jittered corridors from every opening to the center (all carved tiles PROTECTED) → structure
## generator → decoration → **repair** (seal small unreachable pockets, corridor-connect big
## ones, ratio-erode until the reachable floor fraction holds) → final reachability flood fill →
## debug validate → populate.
##
## RNG: one rng, seeded [world_seed, NS_INTERIOR, origin_slot.x, origin_slot.y]. Consumption
## order: corridor walks (spec.passages order), then the structure generator, then decoration.
## The repair pass draws no RNG at all — it is pure grid surgery, so it can run after generation
## without disturbing any of the above draws or their downstream (Population) stream.
extends RefCounted

# Logical tile classes. Byte values in RoomOutput.tile_grid; PROTECTED is the
# separate parallel mask, never a class value.
const FLOOR := 0
const WALL := 1
const BLOCKER := 2
const DECOR_FLOOR := 3


## Build the interior.
static func build(spec: RoomSpec, config: GenConfig, world_seed: int) -> RoomOutput:
	var w := spec.size_slots.x * config.room_slot_tiles
	var h := spec.size_slots.y * config.room_slot_tiles
	var openings := _opening_tiles(spec, w, h)
	var rng := config.rng_for([world_seed, WgHash.NS_INTERIOR,
			spec.origin_slot.x, spec.origin_slot.y] as Array[int])

	var grid := PackedByteArray()
	grid.resize(w * h)               # zero-filled == FLOOR (step 1)
	var prot := PackedByteArray()
	prot.resize(w * h)

	# Step 2 — shell: wall the whole perimeter, then erase (and protect) the openings.
	# Void-facing sides simply keep their wall.
	for x in w:
		grid[x] = WALL
		grid[(h - 1) * w + x] = WALL
	for y in h:
		grid[y * w] = WALL
		grid[y * w + w - 1] = WALL
	for i in openings.size():
		grid[openings[i]] = FLOOR
		prot[openings[i]] = 1

	# Per-biome shell overrides: resolve once, thread explicitly (no config reads inside the
	# shell shaping itself, so it stays a pure function of its inputs).
	var biome := config.biome_by_id(spec.biome_id)
	var depth_dial := config.wall_extra_depth
	var erode_dial := config.wall_outer_erode
	var period_dial := config.wall_noise_period
	var radius_dial := config.corner_radius
	var inset_dial := config.wall_inset_max
	if biome != null:
		depth_dial = _dial(biome.wall_extra_depth, config.wall_extra_depth)
		erode_dial = _dial(biome.wall_outer_erode, config.wall_outer_erode)
		period_dial = _dial(biome.wall_noise_period, config.wall_noise_period)
		radius_dial = _dial(biome.corner_radius, config.corner_radius)
		inset_dial = _dial(biome.wall_inset_max, config.wall_inset_max)

	# Step 2b — organic shaping: erode the straight shell into a wobbly band and round the
	# corners. Runs before the corridor star, which carves (and protects) its way through.
	_shape_shell(grid, prot, w, h, spec, config, world_seed,
			depth_dial, erode_dial, period_dial, radius_dial, inset_dial)

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
	if rt != null and rt.generator != null:
		rt.generator.run(grid, prot, w, h, rng, spec)

	# Step 5 — decoration: non-blocking DECOR_FLOOR at the biome's density; PROTECTED tiles are
	# fair game because decor never blocks. Blocking decor is the structure generators' business.
	if biome != null and biome.decor_density > 0.0:
		var th := WgHash.threshold(biome.decor_density)
		# rng.randi() < th inlined (== WgHash.chance) — the call overhead dominates this
		# per-tile loop in GDScript.
		for i in grid.size():
			if grid[i] == FLOOR and rng.randi() < th:
				grid[i] = DECOR_FLOOR

	# Step 6 — repair: pure, RNG-free grid surgery restoring the reachability invariant that the
	# retry ladder used to gamble on. See _repair for the six-step spec.
	var reach := _repair(grid, prot, w, h, cx, cy, config)

	var out := RoomOutput.new()
	out.origin_slot = spec.origin_slot
	out.width = w
	out.height = h
	out.type_id = spec.type_id
	out.biome_id = spec.biome_id
	out.tile_grid = grid
	out.protected_map = prot
	out.reachability_map = reach

	# Debug assertion only — repair guarantees this by construction; a failure here is a bug,
	# never an expected outcome to retry around.
	_validate(out, openings, config)

	# Step 7 — population: own RNG stream, independent of everything above.
	Population.populate(out, spec, config, world_seed, openings)
	return out


## override_val >= 0 wins (an explicit per-biome shell override); -1 means inherit the
## GenConfig-wide dial.
static func _dial(override_val: int, config_val: int) -> int:
	return override_val if override_val >= 0 else config_val


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
## hashed under NS_WALL_SHAPE, so the wobble flows continuously across the collinear walls of
## adjacent rooms. Protected tiles (openings, corridors) are never written. Void-facing sides
## (spec.void_sides, bit == WorldSpec.SIDE_*) face the sealed outside of the world and never
## erode (their perimeter ring stays sealed). depth/erode/period/radius/inset are the
## already-resolved per-biome dials — this function reads no config.
static func _shape_shell(grid: PackedByteArray, prot: PackedByteArray, w: int, h: int,
		spec: RoomSpec, config: GenConfig, world_seed: int,
		depth_dial: int, erode_dial: int, period_dial: int, radius_dial: int, inset_dial: int) -> void:
	var depth := mini(depth_dial, (mini(w, h) >> 1) - 1)
	var radius := radius_dial
	var erode := clampi(erode_dial, 0, maxi(mini(w, h) >> 2, 0))
	if depth <= 0 and radius <= 0 and erode <= 0:
		return
	var base := config.seed_for([world_seed, WgHash.NS_WALL_SHAPE] as Array[int])
	var ox := spec.origin_slot.x * config.room_slot_tiles
	var oy := spec.origin_slot.y * config.room_slot_tiles
	var period := maxi(period_dial, 1)
	var inset_max := clampi(inset_dial, 0, mini(w, h) >> 2)

	var void_n := (spec.void_sides & (1 << WorldSpec.SIDE_NORTH)) != 0
	var void_e := (spec.void_sides & (1 << WorldSpec.SIDE_EAST)) != 0
	var void_s := (spec.void_sides & (1 << WorldSpec.SIDE_SOUTH)) != 0
	var void_w := (spec.void_sides & (1 << WorldSpec.SIDE_WEST)) != 0

	# A corner is OPEN when both walls meeting there have dissolved into OPEN passages — otherwise the
	# never-carved corner stubs of the four rooms round the same junction fuse into a solid wall island
	# stranded in open ground (the repeating tree knot). Open corners drop their stub + rounding and get
	# a sparse organic scatter instead. Both sides being open guarantees no perpendicular wall — and no
	# void edge (crossings there are DOORs, never OPEN) — needs the corner sealed.
	var open_nw := _side_open(spec, WorldSpec.SIDE_NORTH, false, w, h) and _side_open(spec, WorldSpec.SIDE_WEST, false, w, h)
	var open_ne := _side_open(spec, WorldSpec.SIDE_NORTH, true, w, h) and _side_open(spec, WorldSpec.SIDE_EAST, false, w, h)
	var open_sw := _side_open(spec, WorldSpec.SIDE_SOUTH, false, w, h) and _side_open(spec, WorldSpec.SIDE_WEST, true, w, h)
	var open_se := _side_open(spec, WorldSpec.SIDE_SOUTH, true, w, h) and _side_open(spec, WorldSpec.SIDE_EAST, true, w, h)

	if depth > 0 or erode > 0 or inset_max > 0:
		# NORTH row 0 / SOUTH row h-1 (inward +y / -y); WEST col 0 / EAST col w-1 (inward +x / -x).
		# Each side skips the stub band on a corner column whose corner is open (i==0 / i==length-1).
		_shape_side(grid, prot, base, period, depth, erode, _side_inset(base, spec, 0, inset_max),
				w, oy, 0, ox, void_n, open_nw, open_ne, func(i, k): return k * w + i)
		_shape_side(grid, prot, base, period, depth, erode, _side_inset(base, spec, 1, inset_max),
				w, oy + h - 1, 0, ox, void_s, open_sw, open_se, func(i, k): return (h - 1 - k) * w + i)
		_shape_side(grid, prot, base, period, depth, erode, _side_inset(base, spec, 2, inset_max),
				h, ox, 1, oy, void_w, open_nw, open_sw, func(i, k): return i * w + k)
		_shape_side(grid, prot, base, period, depth, erode, _side_inset(base, spec, 3, inset_max),
				h, ox + w - 1, 1, oy, void_e, open_ne, open_se, func(i, k): return i * w + (w - 1 - k))

	_corner(grid, prot, w, h, 0, 0, 1, 1, base, ox, oy, radius, open_nw)
	_corner(grid, prot, w, h, w - 1, 0, -1, 1, base, ox + w - 1, oy, radius, open_ne)
	_corner(grid, prot, w, h, 0, h - 1, 1, -1, base, ox, oy + h - 1, radius, open_sw)
	_corner(grid, prot, w, h, w - 1, h - 1, -1, -1, base, ox + w - 1, oy + h - 1, radius, open_se)


## Shape one wall of the shell: for each column `i` along it, erode the outer `lo` tiles to FLOOR
## and lay WALL over the band [lo .. hi] inward, where `hi` is the side's base inset plus the
## inner-edge noise depth and `lo` the (decorrelated) outer erosion. `idx_fn(i, k)` maps
## (column, inward depth) → grid index for this side. Erosion is skipped on `void_side` and
## clamped two tiles off each corner, so it can never open the world edge or breach a
## perpendicular wall's shared corner tiles.
static func _shape_side(grid: PackedByteArray, prot: PackedByteArray,
		base: int, period: int, depth: int, erode: int, inset: int, length: int, line: int,
		axis: int, wcoord0: int, void_side: bool, open_start: bool, open_end: bool, idx_fn: Callable) -> void:
	var er := 0 if void_side else erode
	for i in length:
		# Open-corner column (i==0 / i==length-1 with both its sides open): skip the stub band so the
		# junction stays clear — the corner is opened by _open_corner, not sealed here.
		if (i == 0 and open_start) or (i == length - 1 and open_end):
			continue
		# Opening column (OPEN span or door): no band at all. Without this the band SEALS the
		# passage one tile behind its protected perimeter ring, and every open border renders
		# as two straight tree lines with a dead floor channel between them.
		if prot[idx_fn.call(i, 0)] == 1:
			continue
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


## True when `side` has an OPEN passage reaching the requested end (LOW=offset≈0, HIGH=offset+
## width≈side length). Offsets run from the side's low-coordinate end (WEST for N/S, NORTH for
## E/W), per RoomSpec.Passage. DOOR and external crossings never count — only fully-open borders.
static func _side_open(spec: RoomSpec, side: int, at_high: bool, w: int, h: int) -> bool:
	var side_len: int = w if (side == WorldSpec.SIDE_NORTH or side == WorldSpec.SIDE_SOUTH) else h
	for p in spec.passages:
		if p.side != side or p.kind != RoomSpec.KIND_OPEN:
			continue
		if at_high:
			if p.offset_tiles + p.width_tiles >= side_len - 1:
				return true
		elif p.offset_tiles <= 1:
			return true
	return false


## Room-corner shaping: a solid rounded quarter-disc where a wall genuinely turns, or a sparse
## organic tree scatter where the corner is open (both its sides dissolved into passages).
static func _corner(grid: PackedByteArray, prot: PackedByteArray, w: int, h: int,
		cx0: int, cy0: int, sx: int, sy: int, base: int, wx: int, wy: int,
		base_radius: int, is_open: bool) -> void:
	if is_open:
		_open_corner(grid, prot, w, h, cx0, cy0, sx, sy, base, wx, wy, base_radius)
	elif base_radius > 0:
		_round_corner(grid, prot, w, h, cx0, cy0, sx, sy, base, wx, wy, base_radius)


## Open corner: erase the lone leftover perimeter stub so the two open spans meet, then scatter a
## few isolated trees over the corner quadrant — a loose cluster at the junction instead of a solid
## knot. Density is a pure hash of WORLD tile coords (retry-stable, continuous across the seam with
## the three rooms sharing this junction, each scattering its own corner). Never touches PROTECTED
## tiles (openings, corridors) or non-FLOOR tiles.
const _OPEN_CORNER_TREE_CHANCE := 0.06

static func _open_corner(grid: PackedByteArray, prot: PackedByteArray, w: int, h: int,
		cx0: int, cy0: int, sx: int, sy: int, base: int, wx: int, wy: int, base_radius: int) -> void:
	var cidx := cy0 * w + cx0
	if prot[cidx] == 0:
		grid[cidx] = FLOOR
	var r := maxi(base_radius, 3)
	for j in r:
		var y := cy0 + sy * j
		if y < 0 or y >= h:
			break
		var row := y * w
		for i in r:
			var x := cx0 + sx * i
			if x < 0 or x >= w:
				continue
			var idx := row + x
			if prot[idx] == 1 or grid[idx] != FLOOR:
				continue
			var m := WgHash.splitmix64(WgHash.splitmix64(wx + sx * i) ^ WgHash.splitmix64(wy + sy * j))
			if float(WgHash.splitmix64(base ^ m) & 0xFFFF) / 65535.0 < _OPEN_CORNER_TREE_CHANCE:
				grid[idx] = WALL


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
## Consumes the rng in spec.passages order.
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


## Step 6 — deterministic, RNG-free repair. Guarantees on return: every walkable
## (FLOOR/DECOR_FLOOR) tile is reachable from the room centre, and the reachable count meets
## config.min_reachable_floor_ratio. Six sub-steps:
##   1. Flood fill from centre.
##   2. Row-major scan for a walkable tile with reach==0 → BFS its whole connected component
##      (the pocket), in discovery order (N,E,S,W).
##   3. Pocket size <= pocket_seal_max_tiles → seal every pocket tile to WALL (skipping any
##      PROTECTED tile — corridor/opening tiles are reachable by construction, so one can never
##      appear in an unreachable pocket; the skip is a can't-happen guard, not a real branch).
##   4. Bigger pocket → multi-source BFS from every pocket tile, stepping only through
##      non-walkable (WALL/BLOCKER) tiles in neighbour order N,E,S,W, until the frontier meets a
##      reach==1 tile; walk the parent chain back and door-width-stamp (_carve: FLOOR+PROTECTED)
##      every tile on it, clamped inside the perimeter ring ([1,w-2]/[1,h-2]). Re-flood and
##      restart the scan (a connect can absorb pockets discovered later in the same pass; each
##      restart strictly grows `reach`, so this terminates).
##   5. Ratio repair: while reach.count(1) is under the ratio target, collect every WALL/BLOCKER
##      tile inside the ring that 4-neighbours a reach==1 tile, flip them all to FLOOR in one
##      pass, and re-flood. A no-op pass is impossible with a reachable centre (push_error+break
##      as a can't-happen guard).
##   6. Final flood fill is whatever the loop above left in `reach` — returned directly.
static func _repair(grid: PackedByteArray, prot: PackedByteArray, w: int, h: int,
		cx: int, cy: int, config: GenConfig) -> PackedByteArray:
	var reach := _flood_fill(grid, w, h, cx, cy)

	var restart := true
	while restart:
		restart = false
		var visited := PackedByteArray()
		visited.resize(w * h)
		for i in w * h:
			if reach[i] == 1 or visited[i] == 1:
				continue
			if grid[i] != FLOOR and grid[i] != DECOR_FLOOR:
				continue
			var pocket := _collect_pocket(grid, reach, visited, w, h, i)
			if pocket.size() <= config.pocket_seal_max_tiles:
				for j in pocket.size():
					var idx: int = pocket[j]
					if prot[idx] == 0:   # can't-happen guard: PROTECTED tiles are reachable by construction
						grid[idx] = WALL
				# Sealing doesn't change `reach` (these tiles were already unreachable) — keep scanning.
			else:
				_connect_pocket(grid, prot, reach, w, h, pocket, config.door_width_tiles)
				reach = _flood_fill(grid, w, h, cx, cy)
				restart = true
				break

	var total := w * h
	var target := int(config.min_reachable_floor_ratio * total)
	while reach.count(1) < target:
		var to_flip := PackedInt32Array()
		for y in range(1, h - 1):
			var row := y * w
			for x in range(1, w - 1):
				var idx := row + x
				if grid[idx] != WALL and grid[idx] != BLOCKER:
					continue
				if reach[idx - 1] == 1 or reach[idx + 1] == 1 or reach[idx - w] == 1 or reach[idx + w] == 1:
					to_flip.append(idx)
		if to_flip.is_empty():
			push_error("RoomBuilder: ratio repair stalled at %d/%d reachable tiles (target %d) — cannot happen with a reachable centre"
					% [reach.count(1), total, target])
			break
		for j in to_flip.size():
			grid[to_flip[j]] = FLOOR
		reach = _flood_fill(grid, w, h, cx, cy)

	return reach


## BFS the connected component of walkable (FLOOR/DECOR_FLOOR), reach==0 tiles starting at
## `start`, in neighbour order N,E,S,W. Marks `visited` as it goes; does not touch `reach`.
static func _collect_pocket(grid: PackedByteArray, reach: PackedByteArray, visited: PackedByteArray,
		w: int, h: int, start: int) -> PackedInt32Array:
	var pocket := PackedInt32Array()
	var stack := PackedInt32Array()
	stack.resize(w * h)
	var sp := 0
	stack[sp] = start
	sp += 1
	visited[start] = 1
	while sp > 0:
		sp -= 1
		var idx := stack[sp]
		pocket.append(idx)
		var x := idx % w
		@warning_ignore("integer_division")
		var y := idx / w
		if y > 0:
			var n := idx - w
			if visited[n] == 0 and reach[n] == 0 and (grid[n] == FLOOR or grid[n] == DECOR_FLOOR):
				visited[n] = 1
				stack[sp] = n
				sp += 1
		if x < w - 1:
			var e := idx + 1
			if visited[e] == 0 and reach[e] == 0 and (grid[e] == FLOOR or grid[e] == DECOR_FLOOR):
				visited[e] = 1
				stack[sp] = e
				sp += 1
		if y < h - 1:
			var s := idx + w
			if visited[s] == 0 and reach[s] == 0 and (grid[s] == FLOOR or grid[s] == DECOR_FLOOR):
				visited[s] = 1
				stack[sp] = s
				sp += 1
		if x > 0:
			var wv := idx - 1
			if visited[wv] == 0 and reach[wv] == 0 and (grid[wv] == FLOOR or grid[wv] == DECOR_FLOOR):
				visited[wv] = 1
				stack[sp] = wv
				sp += 1
	return pocket


## Multi-source BFS from every tile of `pocket`, stepping only through non-walkable
## (WALL/BLOCKER) tiles — walkable neighbours can only be pocket tiles themselves (already
## visited) or the reach==1 target (the search goal), since `pocket` is already a maximal
## walkable component. Neighbour order N,E,S,W. On reaching a reach==1 tile, backtracks the
## parent chain and door-width-stamps every tile on it via `_carve`, clamped inside the
## perimeter ring so a connect can never breach the outer sealed shell.
static func _connect_pocket(grid: PackedByteArray, prot: PackedByteArray, reach: PackedByteArray,
		w: int, h: int, pocket: PackedInt32Array, door_width: int) -> void:
	var visited := PackedByteArray()
	visited.resize(w * h)
	var parent := PackedInt32Array()
	parent.resize(w * h)
	for i in w * h:
		parent[i] = -1
	var queue := PackedInt32Array()
	queue.resize(w * h)
	var qh := 0
	var qt := 0
	for j in pocket.size():
		var idx: int = pocket[j]
		if visited[idx] == 0:
			visited[idx] = 1
			queue[qt] = idx
			qt += 1

	var hit := -1
	while qh < qt:
		var idx := queue[qh]
		qh += 1
		if reach[idx] == 1:
			hit = idx
			break
		var x := idx % w
		@warning_ignore("integer_division")
		var y := idx / w
		if y > 0:
			var n := idx - w
			if visited[n] == 0 and (grid[n] == WALL or grid[n] == BLOCKER or reach[n] == 1):
				visited[n] = 1
				parent[n] = idx
				queue[qt] = n
				qt += 1
		if x < w - 1:
			var e := idx + 1
			if visited[e] == 0 and (grid[e] == WALL or grid[e] == BLOCKER or reach[e] == 1):
				visited[e] = 1
				parent[e] = idx
				queue[qt] = e
				qt += 1
		if y < h - 1:
			var s := idx + w
			if visited[s] == 0 and (grid[s] == WALL or grid[s] == BLOCKER or reach[s] == 1):
				visited[s] = 1
				parent[s] = idx
				queue[qt] = s
				qt += 1
		if x > 0:
			var wv := idx - 1
			if visited[wv] == 0 and (grid[wv] == WALL or grid[wv] == BLOCKER or reach[wv] == 1):
				visited[wv] = 1
				parent[wv] = idx
				queue[qt] = wv
				qt += 1

	if hit < 0:
		push_error("RoomBuilder: repair could not find a wall-through path to connect an unreachable pocket")
		return

	var half := door_width >> 1
	var cur := hit
	while cur != -1:
		var x := cur % w
		@warning_ignore("integer_division")
		var y := cur / w
		var x0 := clampi(x - half, 1, w - 2)
		var x1 := clampi(x + half, 1, w - 2)
		var y0 := clampi(y - half, 1, h - 2)
		var y1 := clampi(y + half, 1, h - 2)
		_carve(grid, prot, w, h, x0, x1, y0, y1)
		cur = parent[cur]


## Debug assertion only, run after repair — a failure here is always a bug (repair guarantees
## these invariants by construction), never a case that retries. push_error and keep going.
static func _validate(out: RoomOutput, openings: PackedInt32Array, config: GenConfig) -> bool:
	var ok := true
	for i in openings.size():
		if out.reachability_map[openings[i]] == 0:
			push_error("RoomBuilder: opening tile unreachable after repair, origin_slot %s" % out.origin_slot)
			ok = false
	var total := out.width * out.height
	var reachable := out.reachability_map.count(1)
	if reachable < int(config.min_reachable_floor_ratio * total):
		push_error("RoomBuilder: reachable ratio %.3f below min_reachable_floor_ratio after repair, origin_slot %s"
				% [float(reachable) / total, out.origin_slot])
		ok = false
	return ok
