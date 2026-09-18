extends Node
## Run: godot --headless --path game res://tests/generation/test_breather_chance.tscn


func _ready() -> void:
	var graph := WorldGraph.new()
	graph.plan = WorldPlan.new()
	for id: StringName in [&"none", &"all"]:
		var biome := BiomePlan.new()
		biome.resource = BiomeResource.new()
		biome.resource.breather_chance = 0.0 if id == &"none" else 1.0
		graph.plan.biomes[id] = biome
		for role: int in GeneratedRoom.Role.values():
			var room := GeneratedRoom.new()
			room.plan = RoomPlan.new()
			room.plan.biome = id
			room.plan.key = "%s/%d" % [id, role]
			room.role = role
			graph.rooms[room.plan.key] = room
	RoomRoles.breathe(graph)
	for id: StringName in graph.plan.biomes:
		for role: int in GeneratedRoom.Role.values():
			var expected := GeneratedRoom.Role.BREATHER if id == &"all" and role == GeneratedRoom.Role.TESTING else role
			if graph.rooms["%s/%d" % [id, role]].role != expected:
				push_error("Breather chance changed the wrong role in %s: %d" % [id, role])
				get_tree().quit(1)
				return
	print("Per-biome breather chance passed")
	get_tree().quit()
