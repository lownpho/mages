class_name MacroLattice
extends RefCounted
## The macro grid's true shape. Each macro cell is the Voronoi cell of its grid square's centre moved
## by a hashed offset, so where four squares meet, the cells meet at two three-way junctions a short
## edge apart. No cell border carries on straight through a junction, so none lines up with others
## into a line across the World. An outline reads only the centres two squares around it, so cells
## still build independently.
##
## Moving centres shrinks some cells, so a centre moves less the more of their squares the set pieces
## of the cells around it claim: fully while each claims at most FULL_BEND_SHARE, not at all from
## WorldPlanner.SET_PIECE_SHARE. A crowded cell and its neighbours then sit on the grid, which keeps
## the crowded cell square.

## How far a centre moves along each axis, in tiles. At this much, the edge between two side-by-side
## cells stays around half a cell long or more, room for a port, while the jogs between junctions
## average about 20 tiles.
const JITTER := 24.0
## The share of a cell's square its set pieces' discs may claim before the centres around it move less.
const FULL_BEND_SHARE := 0.25
## How near an edge a point counts as on it, in tiles: clipping moves vertices far less.
const _ON_EDGE := 0.01
## Grid squares of centres kept past the World on each side, beyond the two rings an outline reads.
const _PAD := 3
## Side of the square bins, in tiles, that list which cells may hold a point of a grid square.
const _BIN := 8
@warning_ignore("integer_division")
const _BINS := WorldPlan.CELL / _BIN

var size := Vector2i.ZERO
## The furthest any cell's outline strays past its grid square, in tiles.
var reach := 0.0
## Centres of the grid squares from (-_PAD, -_PAD), row by row, _width to a row.
var _centres := PackedVector2Array()
var _width := 0
var _height := 0
var _outlines: Dictionary[Vector2i, PackedVector2Array] = {}
## Grid square -> its bins' candidate cells (see _build_bins). cell_at() runs once per tile streamed,
## so it keeps the square it last read.
var _square_bins: Dictionary[Vector2i, Array] = {}
var _bins_square := Vector2i(1 << 30, 1 << 30)
var _bins: Array[PackedInt32Array] = []
## Edge ends by (upper or left cell x, y, 1 for its right edge or 0 for its lower one).
var _edges: Dictionary[Vector3i, PackedVector2Array] = {}


func _init(plan: WorldPlan) -> void:
	size = plan.size
	var bends := _bends(plan)
	_width = size.x + 2 * _PAD
	_height = size.y + 2 * _PAD
	_centres.resize(_width * _height)
	for j in range(-_PAD, size.y + _PAD):
		for i in range(-_PAD, size.x + _PAD):
			var bend := 1.0
			for dj in range(-1, 2):
				for di in range(-1, 2):
					bend = minf(bend, bends.get(Vector2i(i + di, j + dj), 1.0))
			var rng := plan.rng(WorldHash.NS_LATTICE, "centre/%d,%d" % [i, j])
			_centres[(j + _PAD) * _width + i + _PAD] = (Vector2(i, j) + Vector2(0.5, 0.5)) * WorldPlan.CELL \
					+ Vector2(rng.randf_range(-JITTER, JITTER), rng.randf_range(-JITTER, JITTER)) * bend
	for j in size.y:
		for i in size.x:
			var square := Rect2(Vector2(i, j) * WorldPlan.CELL, Vector2.ONE * WorldPlan.CELL)
			for point in outline(Vector2i(i, j)):
				reach = maxf(reach, maxf(maxf(square.position.x - point.x, point.x - square.end.x),
						maxf(square.position.y - point.y, point.y - square.end.y)))


## A grid square's moved centre; squares far beyond the World keep theirs.
func centre(coord: Vector2i) -> Vector2:
	var i := coord.x + _PAD
	var j := coord.y + _PAD
	if i < 0 or j < 0 or i >= _width or j >= _height:
		return (Vector2(coord) + Vector2(0.5, 0.5)) * WorldPlan.CELL
	return _centres[j * _width + i]


## The macro cell holding a point: the nearest centre, which is always one of the nine around the
## point's grid square. Streaming asks once per tile, so it takes scalars.
func cell_at(x: float, y: float) -> Vector2i:
	var column := floori(x / WorldPlan.CELL)
	var row := floori(y / WorldPlan.CELL)
	if column != _bins_square.x or row != _bins_square.y:
		_bins_square = Vector2i(column, row)
		_bins = square_bins(_bins_square)
	var bin := _bins[mini(floori((y - row * WorldPlan.CELL) / _BIN), _BINS - 1) * _BINS \
			+ mini(floori((x - column * WorldPlan.CELL) / _BIN), _BINS - 1)]
	if bin.size() == 2:
		return Vector2i(bin[0], bin[1])
	var best := 0
	var least := INF
	for n in range(0, bin.size(), 2):
		var at := centre(Vector2i(bin[n], bin[n + 1]))
		var distance := (at.x - x) * (at.x - x) + (at.y - y) * (at.y - y)
		if distance < least:
			least = distance
			best = n
	return Vector2i(bin[best], bin[best + 1])


## A cell's convex outline, clockwise.
func outline(coord: Vector2i) -> PackedVector2Array:
	if _outlines.has(coord):
		return _outlines[coord]
	var own := centre(coord)
	var box := Rect2(Vector2(coord) * WorldPlan.CELL, Vector2.ONE * WorldPlan.CELL).grow(WorldPlan.CELL)
	var poly := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
	for dj in range(-2, 3):
		for di in range(-2, 3):
			if di != 0 or dj != 0:
				var other := centre(coord + Vector2i(di, dj))
				poly = PowerCells.clip(poly, other - own, (other.length_squared() - own.length_squared()) * 0.5)
	# A bisector through a corner already cut leaves that corner twice.
	var corners := PackedVector2Array()
	for point in poly:
		if corners.is_empty() or not point.is_equal_approx(corners[-1]):
			corners.append(point)
	if corners.size() > 1 and corners[0].is_equal_approx(corners[-1]):
		corners.remove_at(corners.size() - 1)
	_outlines[coord] = corners
	return corners


## The edge a cell shares with its side neighbour toward direction, as its two ends: top first on an
## edge between side-by-side cells, left first between stacked ones. Both cells read it from the one
## above or to the left, so they agree exactly. Empty when the cells don't touch.
func edge(coord: Vector2i, direction: Vector2i) -> PackedVector2Array:
	var first := coord if direction.x + direction.y > 0 else coord + direction
	var step := Vector2i(absi(direction.x), absi(direction.y))
	# Exposure asks for every vertex of every Room along an edge, so each edge is found once.
	var key := Vector3i(first.x, first.y, step.x)
	if _edges.has(key):
		return _edges[key]
	_edges[key] = _find_edge(first, step)
	return _edges[key]


func _find_edge(first: Vector2i, step: Vector2i) -> PackedVector2Array:
	var a := centre(first)
	var b := centre(first + step)
	var normal := (b - a).normalized()
	var limit := (b.length_squared() - a.length_squared()) * 0.5 / a.distance_to(b)
	var ends := PackedVector2Array()
	for point in outline(first):
		if absf(point.dot(normal) - limit) < _ON_EDGE:
			if ends.size() < 2:
				ends.append(point)
			elif (point.y if step.x != 0 else point.x) < (ends[0].y if step.x != 0 else ends[0].x):
				ends[0] = point
			elif (point.y if step.x != 0 else point.x) > (ends[1].y if step.x != 0 else ends[1].x):
				ends[1] = point
	if ends.size() < 2:
		return PackedVector2Array()
	if (ends[0].y if step.x != 0 else ends[0].x) > (ends[1].y if step.x != 0 else ends[1].x):
		ends.reverse()
	return ends


## The point a fraction t of the way along a cell's edge toward direction, from its first end.
func edge_point(coord: Vector2i, direction: Vector2i, t: float) -> Vector2:
	var ends := edge(coord, direction)
	return ends[0].lerp(ends[1], t)


## The point along tiles from the first end of a cell's edge toward direction.
func point_along(coord: Vector2i, direction: Vector2i, along: float) -> Vector2:
	var ends := edge(coord, direction)
	return ends[0] + (ends[1] - ends[0]).normalized() * along


## How far along a cell's edge toward direction a point lies, in tiles from its first end.
func along_edge(coord: Vector2i, direction: Vector2i, point: Vector2) -> float:
	var ends := edge(coord, direction)
	return (point - ends[0]).dot((ends[1] - ends[0]).normalized())


## The unit vector along a cell's edge toward direction, from its first end to its second.
func edge_tangent(coord: Vector2i, direction: Vector2i) -> Vector2:
	var ends := edge(coord, direction)
	return (ends[1] - ends[0]).normalized()


## The unit normal of a cell's edge toward direction, pointing into the cell.
func inward(coord: Vector2i, direction: Vector2i) -> Vector2:
	return (centre(coord) - centre(coord + direction)).normalized()


## Whether a point lies on a cell's edge toward direction.
func on_edge(coord: Vector2i, direction: Vector2i, point: Vector2) -> bool:
	var ends := edge(coord, direction)
	return ends.size() == 2 and point.distance_to(Geometry2D.get_closest_point_to_segment(point, ends[0], ends[1])) < _ON_EDGE


## For each bin of a grid square, _BIN tiles to a side row by row, the cells among the nine around it
## whose centre can be nearest somewhere in the bin: (x, y) pairs in the order cell_at() compares them,
## so ties resolve as a full scan would. WorldGraph's ownership bins build on them.
func square_bins(square: Vector2i) -> Array[PackedInt32Array]:
	if not _square_bins.has(square):
		_square_bins[square] = _build_bins(square.x, square.y)
	return _square_bins[square]


func _build_bins(column: int, row: int) -> Array[PackedInt32Array]:
	var candidates: Array[Vector2i] = []
	var xs := PackedFloat64Array()
	var ys := PackedFloat64Array()
	for j in range(row - 1, row + 2):
		for i in range(column - 1, column + 2):
			candidates.append(Vector2i(i, j))
			var at := centre(Vector2i(i, j))
			xs.append(at.x)
			ys.append(at.y)
	var reach := _BIN * sqrt(2.0) * 0.5
	var bins: Array[PackedInt32Array] = []
	var lows := PackedFloat64Array()
	lows.resize(candidates.size())
	for by in _BINS:
		var middle_y := row * WorldPlan.CELL + (by + 0.5) * _BIN
		for bx in _BINS:
			var middle_x := column * WorldPlan.CELL + (bx + 0.5) * _BIN
			var least_high := INF
			for n in candidates.size():
				var distance := sqrt((xs[n] - middle_x) * (xs[n] - middle_x) + (ys[n] - middle_y) * (ys[n] - middle_y))
				var near := maxf(distance - reach, 0.0)
				lows[n] = near * near
				least_high = minf(least_high, (distance + reach) * (distance + reach))
			var bin := PackedInt32Array()
			for n in candidates.size():
				if lows[n] <= least_high + 0.01:
					bin.append(candidates[n].x)
					bin.append(candidates[n].y)
			bins.append(bin)
	return bins


## Each owned cell's bend in [0, 1]: 1 while its set pieces' disc squares, as WorldPlanner counts them,
## claim at most FULL_BEND_SHARE of its square, falling to 0 at WorldPlanner.SET_PIECE_SHARE.
static func _bends(plan: WorldPlan) -> Dictionary[Vector2i, float]:
	var bends: Dictionary[Vector2i, float] = {}
	for coord in plan.cells:
		var claimed := 0
		for room in plan.cells[coord].rooms:
			if room.is_set_piece():
				claimed += WorldPlanner.disc_square(plan.radii[room.kind_name()])
		var share := float(claimed) / WorldPlanner.CELL_AREA
		bends[coord] = clampf((WorldPlanner.SET_PIECE_SHARE - share) / (WorldPlanner.SET_PIECE_SHARE - FULL_BEND_SHARE), 0.0, 1.0)
	return bends
