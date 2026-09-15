extends Node
## Headless test for MacroLattice, the macro grid's irregular cells. On the shipped World and the small
## fixture at their seeds: cell_at() agrees with every outline away from the edges themselves, no
## outline strays past reach or half a cell, every edge between side-by-side owned cells is long
## enough for a port, both cells beside it find the same port point on it, and no corner of the grid
## keeps four cells meeting at one point. On the small fixture with every set piece at its largest
## radius, a cell whose discs claim WorldPlanner.SET_PIECE_SHARE of it keeps its square. Run:
##   godot --headless --path game res://tests/generation/test_macro_lattice.tscn

## Random points per World checked against the outlines.
const SAMPLES := 6000
## Points this near an outline edge may fall either side of it.
const EDGE_TOLERANCE := 0.01
## The shortest edge between side-by-side owned cells, in tiles: ports sit in its middle half.
const MIN_EDGE := 40.0

var _fails: Array[String] = []


func _ready() -> void:
	for fixture: WorldFixture in [WorldFixture.shipped(), WorldFixture.small()]:
		for world_seed in fixture.seeds:
			var plan := fixture.plan(world_seed)
			var label := "%s seed %d" % ["shipped" if fixture.seeds == WorldFixture.SHIPPED_SEEDS else "small", world_seed]
			_check_outlines(plan, label)
			_check_edges(plan, label)
	_check_crowded_square()
	if _fails.is_empty():
		print("ALL PASS")
		get_tree().quit(0)
	else:
		for fail in _fails:
			print("  FAIL: ", fail)
		print("FAILED: %d" % _fails.size())
		get_tree().quit(1)


## Every point cell_at() puts in a grid cell lies in that cell's outline and no other, and every point
## it puts outside the grid in none, unless it lies on an edge.
func _check_outlines(plan: WorldPlan, label: String) -> void:
	var lattice := plan.lattice
	_check(lattice.reach < WorldPlan.CELL * 0.5, "%s: outlines stray %.1f tiles, past half a cell" % [label, lattice.reach])
	var outlines: Dictionary[Vector2i, PackedVector2Array] = {}
	var bounds: Dictionary[Vector2i, Rect2] = {}
	for y in plan.size.y:
		for x in plan.size.x:
			var coord := Vector2i(x, y)
			var outline := lattice.outline(coord)
			outlines[coord] = outline
			var box := Rect2(outline[0], Vector2.ZERO)
			for point in outline:
				box = box.expand(point)
			bounds[coord] = box
			var square := Rect2(Vector2(coord) * WorldPlan.CELL, Vector2.ONE * WorldPlan.CELL)
			_check(square.grow(lattice.reach + EDGE_TOLERANCE).encloses(box), "%s: cell %s's outline %s strays past reach" % [label, coord, box])
	var rng := RandomNumberGenerator.new()
	rng.seed = plan.world_seed
	for n in SAMPLES:
		var point := Vector2(rng.randf_range(-lattice.reach, plan.size.x * WorldPlan.CELL + lattice.reach),
				rng.randf_range(-lattice.reach, plan.size.y * WorldPlan.CELL + lattice.reach))
		var at := lattice.cell_at(point.x, point.y)
		var holders: Array[Vector2i] = []
		for coord in outlines:
			# The bounds come first: is_point_in_polygon can claim points far outside a polygon.
			if bounds[coord].has_point(point) and Geometry2D.is_point_in_polygon(point, outlines[coord]):
				holders.append(coord)
		var expected: Array[Vector2i] = []
		if outlines.has(at):
			expected.append(at)
		if holders != expected and _edge_distance(point, outlines, bounds) > EDGE_TOLERANCE:
			_fails.append("%s: cell_at puts %s in %s, but outlines %s hold it" % [label, point, at, holders])
			return


## Side-by-side owned cells share an edge of at least MIN_EDGE tiles with the same port point from both
## sides, on the edge; and at no grid corner do all four squares' cells meet at one point.
func _check_edges(plan: WorldPlan, label: String) -> void:
	var lattice := plan.lattice
	for coord in plan.cells:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var other := coord + direction
			if not plan.cells.has(other):
				continue
			var ends := lattice.edge(coord, direction)
			_check(ends.size() == 2 and ends[0].distance_to(ends[1]) >= MIN_EDGE,
					"%s: cells %s and %s share an edge %s shorter than %d tiles" % [label, coord, other, ends, MIN_EDGE])
			if ends.size() != 2:
				continue
			var point := MacroCellGraph.port_point(plan, coord, direction)
			_check(point == MacroCellGraph.port_point(plan, other, -direction),
					"%s: cells %s and %s disagree on their edge's port point" % [label, coord, other])
			_check(lattice.on_edge(coord, direction, point) and lattice.on_edge(other, -direction, point),
					"%s: port point %s between %s and %s isn't on their edge" % [label, point, coord, other])
	var crossings := 0
	for y in range(1, plan.size.y):
		for x in range(1, plan.size.x):
			var meeting := Vector2i(x, y)
			var corner: Array[Vector2i] = [meeting - Vector2i.ONE, meeting - Vector2i(0, 1), meeting - Vector2i(1, 0), meeting]
			# Four cells meet at a point only when their centres lie on one circle.
			var a := lattice.centre(corner[0])
			var centre_of_circle := _circumcentre(a, lattice.centre(corner[1]), lattice.centre(corner[2]))
			if is_equal_approx(centre_of_circle.distance_to(a), centre_of_circle.distance_to(lattice.centre(corner[3]))):
				crossings += 1
	var corners := (plan.size.x - 1) * (plan.size.y - 1)
	_check(corners == 0 or crossings < corners, "%s: every grid corner still meets four cells at one point" % label)


## With every radius at its largest, some small-fixture cell's discs claim its whole set-piece share,
## and that cell's outline is its square.
func _check_crowded_square() -> void:
	var plan := WorldFixture.small().plan(WorldFixture.SMALL_SEEDS[0], WorldFixture.radii_at(WorldPlan.RADIUS_MAX))
	var crowded := 0
	for coord in plan.cells:
		var claimed := 0
		for room in plan.cells[coord].rooms:
			if room.is_set_piece():
				claimed += WorldPlanner.disc_square(plan.radii[room.kind_name()])
		if float(claimed) / WorldPlanner.CELL_AREA < WorldPlanner.SET_PIECE_SHARE:
			continue
		crowded += 1
		var square := Rect2(Vector2(coord) * WorldPlan.CELL, Vector2.ONE * WorldPlan.CELL)
		var box := Rect2(plan.lattice.outline(coord)[0], Vector2.ZERO)
		for point in plan.lattice.outline(coord):
			box = box.expand(point)
		var on_square := plan.lattice.outline(coord).size() == 4
		for point in plan.lattice.outline(coord):
			on_square = on_square and (is_equal_approx(point.x, square.position.x) or is_equal_approx(point.x, square.end.x)) \
					and (is_equal_approx(point.y, square.position.y) or is_equal_approx(point.y, square.end.y))
		_check(box.position.is_equal_approx(square.position) and box.end.is_equal_approx(square.end) and on_square,
				"crowded cell %s isn't square: outline %s" % [coord, plan.lattice.outline(coord)])
	_check(crowded > 0, "no small-fixture cell is crowded at the largest radii, so the square rule goes untested")


static func _circumcentre(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	var ux := (a.length_squared() * (b.y - c.y) + b.length_squared() * (c.y - a.y) + c.length_squared() * (a.y - b.y)) / d
	var uy := (a.length_squared() * (c.x - b.x) + b.length_squared() * (a.x - c.x) + c.length_squared() * (b.x - a.x)) / d
	return Vector2(ux, uy)


static func _edge_distance(point: Vector2, outlines: Dictionary[Vector2i, PackedVector2Array], bounds: Dictionary[Vector2i, Rect2]) -> float:
	var nearest := INF
	for coord in outlines:
		if not bounds[coord].grow(1.0).has_point(point):
			continue
		var outline := outlines[coord]
		for n in outline.size():
			nearest = minf(nearest, point.distance_to(Geometry2D.get_closest_point_to_segment(point, outline[n], outline[(n + 1) % outline.size()])))
	return nearest


func _check(ok: bool, message: String) -> void:
	if not ok:
		_fails.append(message)
