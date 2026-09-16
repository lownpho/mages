extends Node
## Headless tests for Room interiors, tiles and streaming, through public outputs: the owner and
## class WorldInteriors gives each World tile, and the cells ChunkStreamer renders. On the small
## fixture World at its authored knobs, each spatial knob at its slider's ends, then all at minimum
## and all at maximum, and on the shipped World at one seed:
##   - walking from the spawn reaches every floor tile of the World (no pocket unreachable from a
##     Passage), every Object spot and landing, each with rock-free ground around it;
##   - every Passage opens floor to floor between its two Rooms;
##   - floor meets another Room's floor only through a Passage between them: neighbouring Rooms'
##     walls agree, across macro-cell edges too.
## Rendered tiles match whatever order chunks are requested in, with caches too small to hold them,
## and after the caches are dropped. Changing decoration leaves the room graph, every class and the
## floor, wall and rock art alone; decoration lies only on floor, in its owner's Zone's tileset. Run:
##   godot --headless --path game res://tests/generation/test_world_tiles.tscn

## Tiles within this distance of an Object spot or landing hold no rock.
const CLEAR_RADIUS := 2.0
## Tiles of the reachability grid past each side of the macro grid, where MacroLattice's outer cells
## stray and the warp reaches further.
const GRID_MARGIN := 64
const _FLOOR := WorldInteriors.FLOOR
const _ROCK := WorldInteriors.ROCK
const _SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var _fails: Array[String] = []


func _ready() -> void:
	var started := Time.get_ticks_msec()
	var shipped := WorldFixture.shipped()
	var small := WorldFixture.small()
	_check(shipped.content.is_valid() and small.content.is_valid(), "test Worlds have content problems")
	for world_seed in small.seeds:
		_check_interiors(small.graph(world_seed), "small seed %d" % world_seed)
	_check_interiors(shipped.graph(shipped.seeds[0]), "shipped seed %d" % shipped.seeds[0])
	_test_sweep(small)
	_test_rendering(small)
	_test_rendering(shipped)
	_test_decoration(small)
	_test_rock_share(small)
	print("world tiles tests took %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	if _fails.is_empty():
		print("ALL PASS")
		get_tree().quit(0)
	else:
		for fail in _fails.slice(0, 60):
			print("  FAIL: ", fail)
		print("FAILED: %d" % _fails.size())
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fails.append(message)


## A rockiness is the share of tiles the rock noise passes its threshold on.
func _test_rock_share(fixture: WorldFixture) -> void:
	var noise := WorldFixture.interiors(fixture.graph(fixture.seeds[0])).rock_noise
	var values := PackedFloat32Array()
	for y in 400:
		for x in 400:
			values.append(noise.get_noise_2d(x, y))
	values.sort()
	for share: float in [0.02, 0.1, 0.3, 0.6]:
		var covered := float(values.size() - values.bsearch(WorldInteriors.rock_threshold(share), false)) / values.size()
		_check(absf(covered - share) <= maxf(0.01, share * 0.15), "rockiness %.2f covers %.3f of tiles" % [share, covered])


func _check_interiors(graph: WorldGraph, label: String) -> void:
	if graph == null:
		_fails.append("%s: built no room graph" % label)
		return
	var field := WorldFixture.interiors(graph)
	# Warped Rooms own tiles a little past the macro grid.
	var bounds := Rect2i(Vector2i.ZERO, graph.plan.size * WorldPlan.CELL).grow(GRID_MARGIN)
	var size := bounds.size
	# 0 no floor, 1 floor, 2 floor reached from the spawn.
	var grid := PackedByteArray()
	grid.resize(size.x * size.y)
	var crossings := 0
	var floor_tiles := 0
	for room in graph.room_list:
		var interior := field.interior(room)
		_check(bounds.encloses(interior.rect), "%s: %s reaches past the test grid: %s" % [label, room.key(), interior.rect])
		var rect := interior.rect.intersection(bounds)
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if interior.class_at(Vector2i(x, y)) == _FLOOR:
					grid[(y - bounds.position.y) * size.x + x - bounds.position.x] = 1
					floor_tiles += 1
		var result := _check_room(field, room, interior, label)
		if result < 0:
			return
		crossings += result
	for key in graph.passages:
		_check_passage(field, graph.passages[key], label)
	_check(crossings > 0, "%s: no Passage crosses a macro-cell edge on tiles" % label)
	var spawn := graph.tile_of(graph.rooms[graph.plan.spawn.key].seed_point) - bounds.position
	if grid[spawn.y * size.x + spawn.x] != 1:
		_fails.append("%s: the spawn %s isn't floor" % [label, spawn + bounds.position])
		return
	var stack := PackedInt32Array([spawn.y * size.x + spawn.x])
	grid[stack[0]] = 2
	var reached := 1
	while not stack.is_empty():
		var at := stack[-1]
		stack.remove_at(stack.size() - 1)
		var x := at % size.x
		for next: int in [at - 1 if x > 0 else -1, at + 1 if x < size.x - 1 else -1, at - size.x, at + size.x]:
			if next >= 0 and next < grid.size() and grid[next] == 1:
				grid[next] = 2
				reached += 1
				stack.append(next)
	if reached < floor_tiles:
		var example := grid.find(1)
		var tile := Vector2i(example % size.x, floori(float(example) / size.x)) + bounds.position
		_fails.append("%s: %d of %d floor tiles aren't reachable from the spawn, e.g. %s owned by %s" % [label, floor_tiles - reached,
				floor_tiles, tile, field.owner_at(tile).key()])
	for key in graph.sites:
		var spot := graph.sites[key].spot - bounds.position
		_check(grid[spot.y * size.x + spot.x] == 2, "%s: site %s at %s isn't reachable floor" % [label, key, spot + bounds.position])


## A Room meets other Rooms' floor only across its Passages, and its spots have no rock around
## them. Returns how many floor-to-floor steps it takes into another macro cell's Rooms, or -1 after
## a failure.
func _check_room(field: WorldInteriors, room: GeneratedRoom, interior: RoomInterior, label: String) -> int:
	var graph := field.graph
	var rect := interior.rect
	var crossings := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var tile := Vector2i(x, y)
			if interior.class_at(tile) != _FLOOR:
				continue
			for side in _SIDES:
				var neighbour := tile + side
				if interior.class_at(neighbour) != RoomInterior.OUTSIDE:
					continue
				var tile_owner := field.owner_at(neighbour)
				if tile_owner == null or field.class_at(neighbour) != _FLOOR:
					continue
				if not graph.passages.has(RoomPassage.pair(room.key(), tile_owner.key())):
					_fails.append("%s: %s's floor at %s meets floor of %s, with no Passage between them" % [label, room.key(), tile, tile_owner.key()])
					return -1
				if tile_owner.plan.cell != room.plan.cell:
					crossings += 1
	for site in room.sites:
		var reach := ceili(CLEAR_RADIUS)
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var tile := site.spot + Vector2i(dx, dy)
				if Vector2(dx, dy).length() <= CLEAR_RADIUS and interior.class_at(tile) == _ROCK:
					_fails.append("%s: rock at %s beside site %s" % [label, tile, site.key])
					return -1
	return crossings


## Floor of one of a Passage's Rooms touches floor of the other near its spot.
func _check_passage(field: WorldInteriors, passage: RoomPassage, label: String) -> void:
	var graph := field.graph
	var a := graph.rooms[passage.a]
	var b := graph.rooms[passage.b]
	var reach := passage.width + WorldInteriors.OPENING_GROWTH + 2
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var tile := passage.spot + Vector2i(dx, dy)
			if field.owner_at(tile) != a or field.class_at(tile) != _FLOOR:
				continue
			for side in _SIDES:
				if field.owner_at(tile + side) == b and field.class_at(tile + side) == _FLOOR:
					return
	_fails.append("%s: %s Passage %s (width %d at %s) opens no floor between its Rooms" % [label, passage.kind_name(), passage.key, passage.width, passage.spot])


## Every interior guarantee with each knob at its slider's ends, then all at minimum and maximum.
func _test_sweep(fixture: WorldFixture) -> void:
	var world_seed := fixture.seeds[0]
	for knob in WorldFixture.KNOBS:
		for end in 2:
			fixture.set_knob(knob, WorldFixture.knob_range(knob)[end])
			_check_interiors(fixture.graph(world_seed), "small %s at %s" % [knob, WorldFixture.knob_range(knob)[end]])
			fixture.restore_knobs()
	for end in 2:
		for knob in WorldFixture.KNOBS:
			fixture.set_knob(knob, WorldFixture.knob_range(knob)[end])
		_check_interiors(fixture.graph(world_seed), "small all at %s" % ["minimum", "maximum"][end])
		fixture.restore_knobs()


## Chunks built in row order, then in shuffled order with caches that hold almost nothing, then
## again after dropping the caches, render the same cells.
func _test_rendering(fixture: WorldFixture) -> void:
	var fixture_name := fixture.content.root.trim_suffix("/").get_file()
	var graph := fixture.graph(fixture.seeds[0])
	var streamer := ChunkStreamer.new()
	streamer.build_world(graph)
	var coords: Array[Vector2i] = []
	# Around the corner where the Ideal path's second macro cell meets its neighbours, and the spawn.
	var corner := streamer.chunk_of(Vector2(graph.plan.path[1] * WorldPlan.CELL * GameConstants.PX_PER_TILE))
	var spawn := streamer.chunk_of(streamer.spawn_position())
	for centre in [corner, spawn]:
		for dy in range(-2, 2):
			for dx in range(-2, 2):
				if not coords.has(centre + Vector2i(dx, dy)):
					coords.append(centre + Vector2i(dx, dy))
	var expected: Dictionary[Vector2i, Dictionary] = {}
	var walls := 0
	for coord in coords:
		var chunk := streamer.assemble_chunk(coord)
		expected[coord] = WorldFixture.rendered(chunk)
		for layer_name: String in expected[coord]:
			if layer_name.ends_with("_wall") or layer_name.ends_with("_rock"):
				walls += expected[coord][layer_name].count(";") + 1
		chunk.free()
	_check(walls > 0, "%s: chunks around %s and %s render no walls or rocks" % [fixture_name, corner, spawn])
	streamer.free()
	var shuffled := coords.duplicate()
	WorldPlanner._shuffle(shuffled, WorldHash.rng(97))
	streamer = ChunkStreamer.new()
	streamer.build_world(fixture.graph(fixture.seeds[0]))
	streamer.interiors.block_capacity = 3
	streamer.interiors.interior_capacity = 1
	for coord: Vector2i in shuffled:
		var chunk := streamer.assemble_chunk(coord)
		_check(WorldFixture.rendered(chunk) == expected[coord], "%s: chunk %s renders differently built in shuffled order with evicting caches" % [fixture_name, coord])
		chunk.free()
	for coord: Vector2i in [shuffled[0], shuffled[-1]]:
		streamer.clear_caches()
		var chunk := streamer.assemble_chunk(coord)
		_check(WorldFixture.rendered(chunk) == expected[coord], "%s: chunk %s renders differently after its caches were dropped" % [fixture_name, coord])
		chunk.free()
	streamer.free()


## Raising every Biome's decoration density and giving one Zone its own decoration tileset and
## density changes only decoration.
func _test_decoration(fixture: WorldFixture) -> void:
	var world_seed := fixture.seeds[0]
	var graph := fixture.graph(world_seed)
	var snapshot := WorldFixture.graph_snapshot(graph)
	var streamer := ChunkStreamer.new()
	streamer.build_world(graph)
	var zone_id: StringName = fixture.content.zones[&"forest"].keys()[0]
	var zone: ZoneResource = fixture.content.zones[&"forest"][zone_id]
	var coords := _zone_chunks(streamer, graph, &"forest", zone_id)
	var before := _render(streamer, coords)
	var classes := _classes(streamer.interiors, coords, streamer.chunk_tiles)
	streamer.free()

	var authored_tileset := zone.decoration_tileset
	var authored_density := zone.decoration_density
	fixture.set_knob(&"decoration_density", 0.6)
	zone.decoration_tileset = load("res://generation/world/biomes/glade/art/glade_veggie_decor_tileset.tres")
	zone.decoration_density = 0.9
	graph = fixture.graph(world_seed)
	_check(WorldFixture.graph_snapshot(graph) == snapshot, "decoration edits changed the room graph")
	streamer = ChunkStreamer.new()
	streamer.build_world(graph)
	var after := _render(streamer, coords)
	_check(_classes(streamer.interiors, coords, streamer.chunk_tiles) == classes, "decoration edits changed tile classes")
	var zone_layer := "forest_%s_decoration" % zone_id
	var decorated := 0
	for coord in coords:
		for layer_name: String in after[coord]:
			if not layer_name.ends_with("_decoration"):
				_check(after[coord][layer_name] == before[coord].get(layer_name, ""), "decoration edits changed %s in chunk %s" % [layer_name, coord])
				continue
			for cell: String in after[coord][layer_name].split(";", false):
				var local := cell.get_slice(":", 0).split(",")
				var tile := coord * streamer.chunk_tiles + Vector2i(local[0].to_int(), local[1].to_int())
				var tile_owner := streamer.interiors.owner_at(tile)
				decorated += 1
				if streamer.interiors.class_at(tile) != _FLOOR or tile_owner == null:
					_fails.append("decoration on %s at %s, which isn't floor" % [layer_name, tile])
					break
				var in_zone := tile_owner.plan.biome == &"forest" and tile_owner.plan.zone == zone_id
				if (layer_name == zone_layer) != in_zone or (not in_zone and layer_name != "%s_decoration" % tile_owner.plan.biome):
					_fails.append("decoration of %s at %s, owned by %s/%s" % [layer_name, tile, tile_owner.plan.biome, tile_owner.plan.zone])
					break
	_check(after.values().any(func(layers: Dictionary) -> bool: return layers.has(zone_layer)), "the Zone's own decoration tileset shows nowhere near its Rooms")
	_check(decorated > 0, "raised decoration density placed no decoration")
	streamer.free()
	fixture.restore_knobs()
	zone.decoration_tileset = authored_tileset
	zone.decoration_density = authored_density


## A block of chunks around a Room of the Zone next to a Room of another.
func _zone_chunks(streamer: ChunkStreamer, graph: WorldGraph, biome: StringName, zone_id: StringName) -> Array[Vector2i]:
	var centre := streamer.chunk_of(streamer.spawn_position())
	for key in graph.passages:
		var passage := graph.passages[key]
		var a := graph.rooms[passage.a].plan
		var b := graph.rooms[passage.b].plan
		if (a.biome == biome and a.zone == zone_id) != (b.biome == biome and b.zone == zone_id):
			centre = streamer.chunk_of((Vector2(passage.spot) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE)
			break
	var out: Array[Vector2i] = []
	for dy in range(-2, 2):
		for dx in range(-2, 2):
			out.append(centre + Vector2i(dx, dy))
	return out


func _render(streamer: ChunkStreamer, coords: Array[Vector2i]) -> Dictionary[Vector2i, Dictionary]:
	var out: Dictionary[Vector2i, Dictionary] = {}
	for coord in coords:
		var chunk := streamer.assemble_chunk(coord)
		out[coord] = WorldFixture.rendered(chunk)
		chunk.free()
	return out


func _classes(field: WorldInteriors, coords: Array[Vector2i], chunk_tiles: int) -> PackedByteArray:
	var out := PackedByteArray()
	for coord in coords:
		for y in chunk_tiles:
			for x in chunk_tiles:
				out.append(field.class_at(coord * chunk_tiles + Vector2i(x, y)))
	return out
