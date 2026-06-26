class_name MacroMap extends RefCounted
## The "tiny overview map" — the only piece allowed global knowledge. It answers the one
## question per-tile rules can't: which biome is this tile? For now that's a low-frequency
## noise threshold (organic Glade/Deepwood blobs across the infinite plane), with the spawn
## pocket pinned to the first biome so the player always starts in the friendly one.
##
## It also owns the guaranteed-walkable trail network (`is_path`) — the connectivity backbone.
## Dungeon sites and region adjacency will live here too; stubbed for this slice.

const SPAWN_RADIUS := 12        # tiles around origin forced to the spawn biome
const DEEPWOOD_THRESHOLD := 0.15  # noise above this is the second biome

# Connectivity backbone: a wobbling grid of always-clear trails. The x=0 and y=0 trails cross
# at origin (so spawn is always on the network) and the grid is connected by construction, so
# the whole walkable plane is one connected piece no matter how dense cover gets. ForestPainter
# never places a tree on a trail cell. PATH_WOBBLE must stay < PATH_CELL/2 - PATH_WIDTH so
# neighbouring trails can't drift into each other and break the lattice.
const PATH_CELL := 34          # tiles between parallel trails (raise = sparser road grid)
const PATH_WIDTH := 2.0        # trail half-width in tiles (clear strip ≈ 2*this + 1)
const PATH_WOBBLE := 10.0      # how far a trail wanders sideways (organic, not ruler-straight)

var _noise: FastNoiseLite
var _path_noise: FastNoiseLite
var _biomes: Array[BiomeResource] = []   # [0] = spawn/default biome, [1] = alternate


func setup(world_seed: int, biomes: Array[BiomeResource]) -> void:
	_biomes = biomes
	_noise = FastNoiseLite.new()
	_noise.seed = world_seed
	_noise.frequency = 0.01        # large, smooth biome regions
	_noise.fractal_octaves = 2
	_path_noise = FastNoiseLite.new()
	_path_noise.seed = world_seed ^ 0x5EED   # decorrelate trails from the biome field
	_path_noise.frequency = 0.03
	_path_noise.fractal_octaves = 2


## Which biome owns this tile. Pure function of the seed → the partition never shifts.
func biome_at(tile: Vector2i) -> BiomeResource:
	if _biomes.size() < 2:
		return _biomes[0]
	if tile.x * tile.x + tile.y * tile.y <= SPAWN_RADIUS * SPAWN_RADIUS:
		return _biomes[0]
	return _biomes[1] if _noise.get_noise_2d(tile.x, tile.y) > DEEPWOOD_THRESHOLD else _biomes[0]


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
