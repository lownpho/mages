extends Node
## How far the shipped World's generated enemies stand from anything that isn't their own Room's
## floor, over several seeds: a wall, a rock, or another Room's tiles. It reads placement only, so
## it says whether enemies sit in the open or hug the walls and the Passage mouths. Run:
##   godot --headless --path game res://tests/generation/report_placement.tscn

const SEEDS: Array[int] = [7, 90210, 1357924680]
## Clearances past this are all reported together.
const REACH := 4


func _ready() -> void:
	var fixture := WorldFixture.shipped()
	var buckets := PackedInt32Array()
	buckets.resize(REACH + 1)
	var hugging_rooms: Dictionary[String, int] = {}
	var total := 0
	for world_seed in SEEDS:
		var graph := fixture.graph(world_seed)
		var generated := WorldEncounters.new(graph, WorldFixture.interiors(graph))
		generated.generate_all()
		for room in graph.room_list:
			var interior := generated.interiors.interior(room)
			var tiles: Array[Vector2i] = []
			for encounter in generated.for_room(room):
				for member in encounter.members:
					tiles.append(member.tile)
			for member in generated.hazards_for_room(room):
				tiles.append(member.tile)
			var hugging := 0
			for tile in tiles:
				var reach := _reach(interior, tile)
				buckets[mini(reach, REACH)] += 1
				total += 1
				if reach < 2:
					hugging += 1
			if hugging > 0:
				hugging_rooms["seed %d %s (%d/%d)" % [world_seed, room.key(), hugging, tiles.size()]] = hugging
	print("%d enemies over %d seeds, by clear tiles between them and the nearest non-floor:" % [total, SEEDS.size()])
	for reach in buckets.size():
		var label := "%d+" % reach if reach == REACH else str(reach)
		print("  %s: %d (%.1f%%)" % [label, buckets[reach], 100.0 * buckets[reach] / total])
	var worst: Array[String] = hugging_rooms.keys()
	worst.sort_custom(func(a: String, b: String) -> bool: return hugging_rooms[a] > hugging_rooms[b])
	print("Rooms placing enemies within 2 tiles of a wall, worst first:")
	for key in worst.slice(0, 15):
		print("  %s" % key)
	print("  ... %d Rooms in all" % worst.size())
	get_tree().quit(0)


## Clear tiles between this one and the nearest that is not the same Room's floor, capped at REACH.
static func _reach(interior: RoomInterior, tile: Vector2i) -> int:
	var nearest := (REACH + 1) * (REACH + 1)
	for y in range(-REACH, REACH + 1):
		for x in range(-REACH, REACH + 1):
			var distance := x * x + y * y
			if distance >= nearest:
				continue
			if interior.class_at(tile + Vector2i(x, y)) != WorldInteriors.FLOOR:
				nearest = distance
	return floori(sqrt(nearest))
