extends Node
## Enemies per ordinary Room by Biome and Challenge on the shipped World, averaged over several
## seeds, for tuning the Challenge curve. Also times building every Room's enemies with interiors
## already cached. Run:
##   godot --headless --path game res://tests/generation/report_density.tscn

const SEEDS: Array[int] = [7, 90210, 1357924680, 11, 23, 314, 2718, 4242]


func _ready() -> void:
	var fixture := WorldFixture.shipped()
	# Biome -> Challenge -> [Rooms, floor tiles, encounters, encounter enemies, Hazards]
	var rows: Dictionary[StringName, Dictionary] = {}
	var build_ms := 0.0
	var floor_ms := 0.0
	var built_rooms := 0
	for world_seed in SEEDS:
		var graph := fixture.graph(world_seed)
		var generated := WorldEncounters.new(graph, WorldFixture.interiors(graph))
		for room in graph.room_list:
			generated.walkable_tiles(room)
		var started := Time.get_ticks_usec()
		for room in graph.room_list:
			generated.walkable_tiles(room)
		floor_ms += (Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec()
		generated.generate_all()
		build_ms += (Time.get_ticks_usec() - started) / 1000.0
		built_rooms += graph.room_list.size()
		for room in graph.room_list:
			if room.role not in [GeneratedRoom.Role.TESTING, GeneratedRoom.Role.TEACHING]:
				continue
			var row: Array = rows.get_or_add(room.plan.biome, {}).get_or_add(room.plan.challenge, [0, 0, 0, 0, 0])
			var room_encounters := generated.for_room(room)
			row[0] += 1
			row[1] += generated.walkable_tiles(room).size()
			row[2] += room_encounters.size()
			for encounter in room_encounters:
				row[3] += encounter.members.size()
			row[4] += generated.hazards_for_room(room).size()
	print("building enemies: %.2f ms per Room over %d Rooms, of which listing floor %.2f ms" % [build_ms / built_rooms,
			built_rooms, floor_ms / built_rooms])
	print("| Biome | C | Rooms | floor | encounters | fighters | Hazards | fighters/100 tiles |")
	print("|---|---|---|---|---|---|---|---|")
	for biome in rows:
		var challenges: Array = rows[biome].keys()
		challenges.sort()
		for challenge: int in challenges:
			var row: Array = rows[biome][challenge]
			var rooms: float = row[0]
			print("| %s | %d | %d | %.0f | %.1f | %.1f | %.1f | %.2f |" % [biome, challenge, row[0], row[1] / rooms,
					row[2] / rooms, row[3] / rooms, row[4] / rooms, 100.0 * row[3] / row[1]])
	get_tree().quit(0)
