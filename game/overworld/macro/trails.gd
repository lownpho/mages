class_name Trails extends RefCounted
## The biome-scale connectivity backbone: guaranteed-clear corridors carved along every graph
## edge, joining the two biome centres it connects. `is_trail(tile)` is true iff the tile lies
## within any corridor; Group F's painter never blocks a trail tile, so the union of corridors
## stays walkable. Because the WorldGraph is connected and every edge (plus every non-embeddable
## `corridor_edge` backstop from Group C) becomes a corridor through both its centres, that union
## is **one connected component passing through every biome centre** — the connectivity guarantee.
##
## A corridor is the set of tiles within HALF_WIDTH of the segment joining its two centres, with
## the centreline displaced sideways by a seeded, endpoint-tapered wobble so it reads organic but
## never detaches from its endpoints. Pure function of the seed (agrees across chunk borders,
## identical on rebuild).
##
## Group E hook: call `add_corridor(a, b)` to register area-scale branch trails off this network
## (e.g. biome entry → area centre); they flow through the same `is_trail`. The corridor math is
## in `_on_corridor`, reusable by that extension.
##
## Corridors are indexed into a uniform bucket grid (`_buckets`): each corridor registers into the
## buckets its inflated bounding box overlaps, so `is_trail(tile)` only tests the handful of
## corridors near that tile, not all of them. Group E adds ~16 branch corridors per biome, so a
## linear scan would make every `is_trail` (and thus every painted tile in Group F) O(all
## corridors); the index keeps it O(local). Semantically identical to a full scan — the index only
## ever *over*-includes candidates, never drops one (bbox+MARGIN covers every tile `_on_corridor`
## can accept).

# Corridor half-width in tiles → a clear strip ~2*HALF_WIDTH+1 wide (≈7).
const HALF_WIDTH := 3.0
# Sideways wander amplitude in tiles. Bounded well under CELL/8 (≈187) so a corridor can never
# stray far enough to detach from its endpoints; kept gentle so the strip stays 4-connected.
const WOBBLE := 30.0
# Low frequency → a smooth centreline (shallow slope), so consecutive along-slices overlap and
# the strip has no diagonal-only pinch points.
const WOBBLE_FREQ := 0.006

const _CH_PHASE := 40   # per-corridor noise phase, so corridors don't wobble in lockstep

# Spatial index cell size in tiles. A corridor's tiles all lie within (HALF_WIDTH + WOBBLE) of its
# segment, so a corridor registers into the buckets its segment bbox — inflated by that MARGIN —
# spans. Bucket >> MARGIN keeps registrations-per-corridor low; small enough that a query bucket
# holds only nearby corridors.
const _BUCKET := 256
const _MARGIN := 34     # ceil(HALF_WIDTH + WOBBLE) + 1

var _seed: int
var _seg_a: Array[Vector2i] = []
var _seg_b: Array[Vector2i] = []
var _seg_phase: Array[float] = []
var _buckets: Dictionary = {}   # Vector2i bucket -> Array[int] corridor indices overlapping it
var _noise: FastNoiseLite
# Memo of is_trail (Vector2i tile -> bool). Near a biome centre every branch corridor is bucketed
# together, so a miss scans ~20 corridors (segment projection + a noise sample each); the painter and
# the encounter flood/clearance pass re-test the same tiles repeatedly. Pure memo — bounded and reset
# in setup like MacroMap's warp cache.
var _trail_cache: Dictionary = {}
const _CACHE_CAP := 120000


## `centers`: node_index -> centre tile (from MacroMap.biome_centers()). `edges` + `corridor_edges`
## are index pairs; both become corridors (a corridor_edge still needs a walkable link).
func setup(world_seed: int, centers: Dictionary, edges: Array[Vector2i], corridor_edges: Array[Vector2i]) -> void:
	_seed = world_seed
	_seg_a.clear()
	_seg_b.clear()
	_seg_phase.clear()
	_buckets.clear()
	_trail_cache.clear()
	_noise = FastNoiseLite.new()
	_noise.seed = world_seed ^ 0x74011   # decorrelate wobble from the biome/warp fields
	_noise.frequency = WOBBLE_FREQ
	_noise.fractal_octaves = 2
	for e in edges:
		_register(centers, e)
	for e in corridor_edges:
		_register(centers, e)


func _register(centers: Dictionary, e: Vector2i) -> void:
	if centers.has(e.x) and centers.has(e.y):
		add_corridor(centers[e.x], centers[e.y])


## Register an extra guaranteed-clear corridor between two tiles. Group E branches area trails
## off the network through this. Phase is hashed from the endpoints so it stays deterministic.
func add_corridor(a: Vector2i, b: Vector2i) -> void:
	var idx := _seg_a.size()
	_seg_a.append(a)
	_seg_b.append(b)
	_seg_phase.append(Hash.value(_seed, a.x + b.x, a.y + b.y, _CH_PHASE) * 10000.0)
	# Register into every bucket the inflated segment bbox overlaps.
	var lo := _bucket_key(mini(a.x, b.x) - _MARGIN, mini(a.y, b.y) - _MARGIN)
	var hi := _bucket_key(maxi(a.x, b.x) + _MARGIN, maxi(a.y, b.y) + _MARGIN)
	for by in range(lo.y, hi.y + 1):
		for bx in range(lo.x, hi.x + 1):
			var key := Vector2i(bx, by)
			var arr: Array = _buckets.get(key, [])
			arr.append(idx)
			_buckets[key] = arr


## True iff the tile lies on any corridor. Pure function of the seed. Only tests corridors indexed
## to the tile's bucket (see `_buckets`) — identical result to scanning all, far cheaper.
func is_trail(tile: Vector2i) -> bool:
	var cached: Variant = _trail_cache.get(tile)
	if cached != null:
		return cached
	var result := false
	var key := _bucket_key(tile.x, tile.y)
	if _buckets.has(key):
		for i in _buckets[key]:
			if _on_corridor(tile, _seg_a[i], _seg_b[i], _seg_phase[i]):
				result = true
				break
	if _trail_cache.size() >= _CACHE_CAP:
		_trail_cache.clear()
	_trail_cache[tile] = result
	return result


# Bucket owning a tile coord. floori so negative coords bucket consistently (int / truncates).
func _bucket_key(x: int, y: int) -> Vector2i:
	return Vector2i(floori(float(x) / _BUCKET), floori(float(y) / _BUCKET))


# Membership in one corridor: project the tile onto the straight segment a→b to get its position
# `along` and signed perpendicular offset `perp`; the wobbled centreline sits at offset `w(along)`,
# tapered to zero at both endpoints (so the corridor always meets its centres). The tile is in the
# corridor when it is between the endpoints and within HALF_WIDTH of that centreline.
func _on_corridor(tile: Vector2i, a: Vector2i, b: Vector2i, phase: float) -> bool:
	var pa := Vector2(a)
	var ab := Vector2(b - a)
	var seg_len := ab.length()
	if seg_len < 1.0:
		return Vector2(tile).distance_to(pa) <= HALF_WIDTH
	var u := ab / seg_len
	var p := Vector2(tile) - pa
	var along := p.dot(u)
	# Rounded endpoint caps: a disc of radius HALF_WIDTH at each centre. Robust against the
	# float rounding that leaves an endpoint fractionally outside [0, seg_len].
	if along <= 0.0:
		return p.length() <= HALF_WIDTH
	if along >= seg_len:
		return Vector2(tile).distance_to(Vector2(b)) <= HALF_WIDTH
	var perp := p.dot(Vector2(-u.y, u.x))
	var taper := sin(PI * along / seg_len)   # 0 at both endpoints, 1 at mid-corridor
	var w := _noise.get_noise_1d(along + phase) * WOBBLE * taper
	return absf(perp - w) <= HALF_WIDTH
