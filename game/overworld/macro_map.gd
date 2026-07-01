class_name MacroMap extends RefCounted
## The "tiny overview map" — the only piece allowed global knowledge. It answers the one
## question per-tile rules can't: which biome is this tile? The world is a **finite region
## grid**: a `world_regions` (e.g. 3×3) block of REGION_SIZE-tile cells centred on the origin.
## Each cell is assigned one biome up-front from the seed — weighted by each biome's
## `region_weight`, but with every eligible biome (weight > 0) guaranteed to appear at least
## once. Region borders are domain-warped so they undulate organically instead of forming
## straight seams. Because regions are large, addressable (`region_of`) and have a computable
## centre (`region_center`), they double as minimap cells and teleport-door destinations.
## Region (0,0) is centred on the origin and pinned to the first biome, so the player always
## spawns in the friendly one. Tiles outside the grid are "off-world" (`biome_at` returns null
## → nothing generated); the outermost in-world ring (`is_world_edge`) is walled with forced
## cover so the world reads as enclosed.
##
## It also owns the guaranteed-walkable trail network (`is_path`) — the connectivity backbone.
## Dungeon sites and region adjacency will live here too; stubbed for this slice.

const SPAWN_RADIUS := 12        # tiles around origin forced to the spawn biome
const REGION_SIZE := 1200       # tiles per region cell (raise = larger biomes, longer to cross)
const REGION_WOBBLE := 120.0    # domain-warp amplitude in tiles; keep << REGION_SIZE/2 so a
								# region's geometric centre stays interior (reliable teleport target)
const BORDER_THICKNESS := 4     # tiles of forced cover ringing the world edge (the natural barrier)
const _CH_REGION := 7           # Hash channel for the per-region weighted pick
const _CH_SHUFFLE := 8          # Hash channel for the deterministic cell shuffle (coverage guarantee)

# Connectivity backbone: a wobbling grid of always-clear trails. The x=0 and y=0 trails cross
# at origin (so spawn is always on the network) and the grid is connected by construction, so
# the whole walkable plane is one connected piece no matter how dense cover gets. ForestPainter
# never places a tree on a trail cell. PATH_WOBBLE must stay < PATH_CELL/2 - PATH_WIDTH so
# neighbouring trails can't drift into each other and break the lattice.
const PATH_CELL := 34          # tiles between parallel trails (raise = sparser road grid)
const PATH_WIDTH := 2.0        # trail half-width in tiles (clear strip ≈ 2*this + 1)
const PATH_WOBBLE := 10.0      # how far a trail wanders sideways (organic, not ruler-straight)

var _seed: int
var _noise: FastNoiseLite          # low-frequency domain-warp field for region borders
var _path_noise: FastNoiseLite
var _biomes: Array[BiomeResource] = []   # [0] = spawn/default biome

var _rmin: Vector2i                # inclusive region-grid bounds (region coords)
var _rmax: Vector2i
var _world_min: Vector2i           # inclusive world bounds (tile coords)
var _world_max: Vector2i
var _region_biomes := {}           # Vector2i region -> int biome index (baked once in setup)


func setup(world_seed: int, biomes: Array[BiomeResource], world_regions := Vector2i(3, 3)) -> void:
	_seed = world_seed
	_biomes = biomes
	_noise = FastNoiseLite.new()
	_noise.seed = world_seed
	_noise.frequency = 0.004       # warps region borders into organic waves
	_noise.fractal_octaves = 2
	_path_noise = FastNoiseLite.new()
	_path_noise.seed = world_seed ^ 0x5EED   # decorrelate trails from the biome field
	_path_noise.frequency = 0.03
	_path_noise.fractal_octaves = 2

	# Grid bounds, centred on origin (region (0,0) contains the spawn).
	var size := Vector2i(maxi(1, world_regions.x), maxi(1, world_regions.y))
	_rmin = Vector2i(-((size.x - 1) / 2), -((size.y - 1) / 2))
	_rmax = _rmin + size - Vector2i.ONE
	var half := REGION_SIZE / 2
	_world_min = _rmin * REGION_SIZE - Vector2i(half, half)
	_world_max = _rmax * REGION_SIZE + Vector2i(half - 1, half - 1)
	_bake_region_biomes()


## Which biome owns this tile, or null if the tile is off-world (nothing is generated there).
## Pure function of the seed → the partition never shifts.
func biome_at(tile: Vector2i) -> BiomeResource:
	if not in_world(tile):
		return null
	if _biomes.size() < 2:
		return _biomes[0]
	if tile.x * tile.x + tile.y * tile.y <= SPAWN_RADIUS * SPAWN_RADIUS:
		return _biomes[0]
	return _biomes[biome_for_region(region_of(tile))]


## True if the tile lies inside the finite world rectangle.
func in_world(tile: Vector2i) -> bool:
	return tile.x >= _world_min.x and tile.x <= _world_max.x \
		and tile.y >= _world_min.y and tile.y <= _world_max.y


## True if the tile is in-world but within BORDER_THICKNESS of the edge — the ring the painter
## fills with forced cover to wall the world in.
func is_world_edge(tile: Vector2i) -> bool:
	if not in_world(tile):
		return false
	return tile.x < _world_min.x + BORDER_THICKNESS or tile.x > _world_max.x - BORDER_THICKNESS \
		or tile.y < _world_min.y + BORDER_THICKNESS or tile.y > _world_max.y - BORDER_THICKNESS


## The region cell owning this tile. Domain-warps the coordinate so borders undulate, then
## snaps to the nearest cell (round-based, so the origin sits at the centre of region (0,0)).
func region_of(tile: Vector2i) -> Vector2i:
	var wx: float = tile.x + _noise.get_noise_2d(tile.x, tile.y) * REGION_WOBBLE
	var wy: float = tile.y + _noise.get_noise_2d(tile.x + 1000.0, tile.y) * REGION_WOBBLE
	return Vector2i(roundi(wx / REGION_SIZE), roundi(wy / REGION_SIZE))


## Biome index assigned to a region (baked in setup). Off-grid regions clamp to the nearest
## edge cell, so the outermost biome extends cleanly to the world boundary.
func biome_for_region(region: Vector2i) -> int:
	var r := Vector2i(clampi(region.x, _rmin.x, _rmax.x), clampi(region.y, _rmin.y, _rmax.y))
	return _region_biomes.get(r, 0)


## The centre of a region, in tile coordinates — teleport-door destination / minimap anchor.
func region_center(region: Vector2i) -> Vector2i:
	return region * REGION_SIZE


## Inclusive region-grid bounds (region coords) — for minimap enumeration / teleport UIs.
func region_bounds() -> Rect2i:
	return Rect2i(_rmin, _rmax - _rmin + Vector2i.ONE)


# Assign every grid cell a biome once, up-front: pin (0,0) to the spawn biome, guarantee each
# eligible biome (region_weight > 0) appears at least once, then fill the rest by weighted
# pick. Pure function of the seed via a Hash-keyed shuffle, so the layout is reproducible.
func _bake_region_biomes() -> void:
	_region_biomes.clear()
	_region_biomes[Vector2i.ZERO] = 0

	var cells: Array[Vector2i] = []
	for y in range(_rmin.y, _rmax.y + 1):
		for x in range(_rmin.x, _rmax.x + 1):
			var c := Vector2i(x, y)
			if c != Vector2i.ZERO:
				cells.append(c)
	# Deterministic shuffle: order cells by a stable per-cell hash.
	var s := _seed
	cells.sort_custom(func(a, b): return Hash.value(s, a.x, a.y, _CH_SHUFFLE) \
		< Hash.value(s, b.x, b.y, _CH_SHUFFLE))

	# Biomes that must appear (weight > 0), minus the spawn biome already placed at (0,0).
	var forced: Array[int] = []
	for i in range(1, _biomes.size()):
		if _biomes[i].region_weight > 0:
			forced.append(i)
	if forced.size() > cells.size():
		push_warning("MacroMap: world too small (%d cells) to fit every biome — some will be missing" % cells.size())

	for idx in cells.size():
		var cell: Vector2i = cells[idx]
		_region_biomes[cell] = forced[idx] if idx < forced.size() else _weighted_pick(cell)


# Weighted biome index for a cell, keyed on the cell so it's stable. Biomes with weight 0 are
# excluded (they never accumulate into the roll).
func _weighted_pick(cell: Vector2i) -> int:
	var total := 0
	for b in _biomes:
		total += b.region_weight
	if total <= 0:
		return 0
	var roll := int(Hash.value(_seed, cell.x, cell.y, _CH_REGION) * total) % total
	for i in _biomes.size():
		roll -= _biomes[i].region_weight
		if roll < 0:
			return i
	return 0


## True if this tile lies on a guaranteed-clear trail. Pure function of the seed, so it agrees
## across chunk borders. A vertical trail near every multiple of PATH_CELL in x (its centreline
## wobbled by noise of y), plus a horizontal trail likewise in y; their union is a connected
## lattice spanning the plane.
func is_path(tile: Vector2i) -> bool:
	# Vertical trail: distance from x to the nearest wobbled multiple of PATH_CELL.
	var wob_v := _path_noise.get_noise_2d(0.0, tile.y) * PATH_WOBBLE
	var dx: float = tile.x - wob_v
	if absf(dx - roundf(dx / PATH_CELL) * PATH_CELL) <= PATH_WIDTH:
		return true
	# Horizontal trail (offset noise sample so it doesn't mirror the vertical one).
	var wob_h := _path_noise.get_noise_2d(1000.0, tile.x) * PATH_WOBBLE
	var dy: float = tile.y - wob_h
	return absf(dy - roundf(dy / PATH_CELL) * PATH_CELL) <= PATH_WIDTH
