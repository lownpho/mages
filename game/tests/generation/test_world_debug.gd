extends Node
## Observable checks for ticket 05's tuning state, selective rebuild boundary and integrated paused
## controls. Run:
##   godot --headless --path game res://tests/generation/test_world_debug.tscn

var _fails: Array[String] = []


func _ready() -> void:
	var started := Time.get_ticks_msec()
	# Entering the World saves the Run; keep that off the player's save.
	GameState.save_path = "user://test_world_debug_save.cfg"
	_test_pending_revert_and_invalidation()
	_test_save_roundtrip_before_rebuild()
	await _test_integrated_controls()
	DirAccess.remove_absolute(GameState.save_path)
	print("world debug tests took %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	if _fails.is_empty():
		print("ALL PASS")
		get_tree().quit(0)
	else:
		for fail in _fails:
			print("  FAIL: ", fail)
		print("FAILED: %d" % _fails.size())
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fails.append(message)


func _test_pending_revert_and_invalidation() -> void:
	var fixture := WorldFixture.small()
	var plan := fixture.plan(fixture.seeds[0])
	var graph := WorldGraph.build(plan)
	var tuner := WorldTuner.new()
	tuner.setup(fixture.content, fixture.seeds[0], plan, graph)
	var biome := &"hollow"
	var original: float = tuner.pending[biome][&"rockiness"]
	var changed := 0.3 if original != 0.3 else 0.25
	tuner.set_knob(biome, &"rockiness", changed)
	_check(tuner.is_pending(biome, &"rockiness"), "knob edit is pending")
	_check(fixture.content.biomes[biome].rockiness == original, "pending edit did not mutate live content")
	tuner.revert_knob(biome, &"rockiness")
	_check(not tuner.is_pending(biome, &"rockiness"), "per-knob revert restored the authored value")
	tuner.set_knob(biome, &"rockiness", changed)
	var old_cells := graph.cells.duplicate()
	var stream_check := _stream_across_biome_edge(graph, biome)
	var rebuilt := tuner.rebuild()
	_check(rebuilt != null, "knob rebuild produced a graph")
	if rebuilt != null:
		for coord in rebuilt.cells:
			var same: bool = rebuilt.cells[coord] == old_cells[coord]
			_check(same == (rebuilt.plan.cells[coord].biome != biome),
					"selective rebuild identity for %s (%s)" % [coord, rebuilt.plan.cells[coord].biome])
		_check(rebuilt.reachable().size() == rebuilt.rooms.size(), "selective rebuild remains reachable")
		_check(WorldFixture.graph_snapshot(rebuilt) == WorldFixture.graph_snapshot(WorldGraph.build(rebuilt.plan)),
				"selective rebuild matches a clean build")
		_check_selective_chunks(stream_check, rebuilt, tuner.last_invalidated_biomes, biome)
	var old_plan := tuner.plan
	var next_radius: int = tuner.pending_radii[&"rare"] + 1
	tuner.set_radius(&"rare", next_radius)
	_check(tuner.rebuild() != null and tuner.plan != old_plan and tuner.last_plan_invalidated,
			"radius edit invalidated the World plan")
	fixture.content.biomes[biome].rockiness = original
	GameState.run_save_eligible = true
	GameState.run_save_disabled_reason = ""


## A one-pixel viewport straddling a Biome edge loads a handful of real chunks on both sides.
func _stream_across_biome_edge(graph: WorldGraph, changed_biome: StringName) -> Dictionary:
	var edge_cell := Vector2i.ZERO
	var direction := Vector2i.ZERO
	for coord in graph.plan.cells:
		if graph.plan.cells[coord].biome != changed_biome:
			continue
		for side: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var other: MacroCellPlan = graph.plan.cells.get(coord + side)
			if other != null and other.biome != changed_biome:
				edge_cell = coord
				direction = side
				break
		if direction != Vector2i.ZERO:
			break
	var viewport := SubViewport.new()
	viewport.size = Vector2i.ONE
	add_child(viewport)
	var root := Node2D.new()
	viewport.add_child(root)
	var streamer := ChunkStreamer.new()
	streamer.prefetch_tiles = 12
	root.add_child(streamer)
	var target := Node2D.new()
	root.add_child(target)
	var camera := Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	target.add_child(camera)
	var edge := graph.plan.lattice.edge_point(edge_cell, direction, 0.5)
	target.position = edge * GameConstants.PX_PER_TILE
	streamer.build_world(graph)
	streamer.target = target
	streamer.prepare()
	var loaded: Array[Vector2i] = []
	var centre := streamer.chunk_of(target.global_position)
	for y in range(centre.y - 3, centre.y + 4):
		for x in range(centre.x - 3, centre.x + 4):
			if streamer.is_chunk_loaded(Vector2i(x, y)):
				loaded.append(Vector2i(x, y))
	var unloaded: Array[Vector2i] = []
	streamer.chunk_unloaded.connect(func(coord: Vector2i) -> void: unloaded.append(coord))
	return {"viewport": viewport, "streamer": streamer, "loaded": loaded, "unloaded": unloaded}


func _check_selective_chunks(check: Dictionary, graph: WorldGraph,
		invalidated: Dictionary[StringName, bool], _changed_biome: StringName) -> void:
	var streamer: ChunkStreamer = check.streamer
	streamer.rebuild_world(graph, invalidated, false)
	var kept := 0
	var dropped := 0
	for coord: Vector2i in check.loaded:
		if check.unloaded.has(coord):
			dropped += 1
			_check(not streamer.is_chunk_loaded(coord),
					"changed-Biome chunk %s was invalidated" % coord)
		else:
			kept += 1
			_check(streamer.is_chunk_loaded(coord),
					"unaffected chunk %s stayed loaded" % coord)
	_check(kept > 0 and dropped > 0, "selective chunk check covered both sides of a Biome edge")
	check.viewport.queue_free()


func _test_save_roundtrip_before_rebuild() -> void:
	var fixture := WorldFixture.small()
	var biome := &"hollow"
	var original_resource: BiomeResource = fixture.content.biomes[biome]
	var copy: BiomeResource = original_resource.duplicate(true)
	var path := "res://tests/generation/fixtures/.ticket05_biome.tres"
	var initial_save := ResourceSaver.save(copy, path)
	_check(initial_save == OK, "temporary authored Biome saved")
	if initial_save != OK:
		return
	copy.take_over_path(path)
	fixture.content.biomes[biome] = copy
	var plan := fixture.plan(fixture.seeds[0])
	var graph := WorldGraph.build(plan)
	var tuner := WorldTuner.new()
	tuner.setup(fixture.content, fixture.seeds[0], plan, graph)
	var applied: float = copy.rockiness
	var changed := 0.3 if applied != 0.3 else 0.2
	tuner.set_knob(biome, &"rockiness", changed)
	var errors := tuner.save_changed()
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as BiomeResource
	_check(errors.is_empty() and loaded != null and loaded.rockiness == changed,
			"Save round-tripped a pending knob before Rebuild")
	_check(copy.rockiness == applied and tuner.applied[biome][&"rockiness"] == applied,
			"Save did not apply the pending knob to the live World")
	fixture.content.biomes[biome] = original_resource
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameState.run_save_eligible = true
	GameState.run_save_disabled_reason = ""


func _test_integrated_controls() -> void:
	var previous_state := _snapshot_state("world_debug")
	GameState.run_save_eligible = true
	GameState.run_save_disabled_reason = ""
	var world: Node2D = load("res://scenes/world.tscn").instantiate()
	world.world_seed = 7
	add_child(world)
	await get_tree().process_frame
	var layer: WorldDebugLayer = world._debug_layer
	_check(layer != null and layer._tabs.get_tab_count() == 2 and layer._side_tabs.get_tab_count() == 2,
			"integrated panel has Map and Combat tabs, the Map switching Layers and Knobs")
	if layer == null:
		world.queue_free()
		return
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	layer._input(tab)
	_check(layer.panel_open and get_tree().paused, "Tab opened the panel and paused the World")
	_check(layer._map.graph == world._graph and layer._map.graph.rooms.size() == world._graph.rooms.size(),
			"debug Map received the complete graph immediately")
	layer._tabs.current_tab = 1
	var picked: StringName = layer.tuner.content.biome_ids()[-1]
	layer.select_biome(picked)
	layer.set_overlay("zones", not layer.overlays.zones)
	_check(DebugState.get_value("world_debug", "tab", -1) == 1
			and StringName(DebugState.get_value("world_debug", "biome", "")) == picked
			and DebugState.get_value("world_debug", "overlay_zones", null) == layer.overlays.zones,
			"tab, selected Biome and overlays persisted")
	layer.set_overlay("biomes", true)
	_check(layer._legends["biomes"].visible
			and layer._legends["biomes"].get_child(0).get_child_count() == layer.tuner.content.biome_ids().size(),
			"the Biomes overlay keys every Biome")
	layer._tabs.current_tab = WorldDebugLayer.TAB_MAP
	layer.set_overlay("follow", true)
	layer._map._process(0.0)
	_check(layer._map.pan == world._player.global_position / GameConstants.PX_PER_TILE,
			"Follow Player centres the debug Map on the player")
	layer.set_overlay("follow", false)
	layer._map.zoom = 3.0
	layer.set_overlay("tiles", true)
	var baked := layer._map.build_tiles(WorldInteriors.NO_DEADLINE)
	var under_player: GeneratedRoom = world._graph.owner_at(Vector2i(layer._map.pan.floor()))
	_check(baked and under_player != null and layer._map.has_tiles(under_player) and layer._legends["tiles"].visible,
			"Walls and Rocks bakes every Room in the debug Map's view")
	layer.set_overlay("tiles", false)
	layer._set_fly(true)
	_check(world._flying and world._streamer.target == world._player and not world._player.is_in_group("player"),
			"fly passes physics, drives streaming and is not an enemy target")
	var before_eligibility := GameState.run_save_eligible
	world._teleport_to_tile(Vector2i(-20, -20))
	var landed := Vector2i((world._player.global_position / GameConstants.PX_PER_TILE).floor())
	_check(world._streamer.interiors.class_at(landed) == WorldInteriors.FLOOR,
			"teleport snapped the player to floor")
	_check(before_eligibility == GameState.run_save_eligible, "movement and fly kept save eligibility")
	var room_size_id := "%s/room_size" % layer.selected_biome
	var room_size: SpinBox = layer._controls[room_size_id]
	var before_size: int = layer.tuner.pending[layer.selected_biome][&"room_size"]
	room_size.value = before_size + (1 if before_size < room_size.max_value else -1)
	_check(layer.tuner.pending[layer.selected_biome][&"room_size"] != before_size,
			"World-tab knob control edits the selected Biome")
	_check(not GameState.run_save_eligible, "knob edit disabled Run saving")
	_check(DebugState.get_value("world_debug", "fly", false), "fly state persisted")
	layer.set_panel_open(false)
	_check(not get_tree().paused, "closing the panel resumed the World")
	# Fly walks the player itself, faster than on foot, and the wheel zooms its camera until it lands.
	var player: CharacterBody2D = world._player
	var from := player.global_position
	Input.action_press("right")
	for _frame in 6:
		await get_tree().physics_frame
	Input.action_release("right")
	_check(player.global_position.x - from.x > player.speed * 6.0 / Engine.physics_ticks_per_second,
			"fly moved the player faster than walking (%.1f px)" % (player.global_position.x - from.x))
	_check(player.animated_sprite.animation == &"run", "the flying player plays its run")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	world._unhandled_input(wheel)
	var camera: Camera2D = player.get_node("Camera2D")
	_check(camera.zoom == Vector2.ONE * 0.5, "the wheel zoomed the flying camera out")
	layer._set_fly(false)
	_check(camera.zoom == Vector2.ONE and player.is_in_group("player"), "landing reset the zoom and the target group")
	world.queue_free()
	await get_tree().process_frame
	_restore_state("world_debug", previous_state)
	GameState.run_save_eligible = true
	GameState.run_save_disabled_reason = ""


func _snapshot_state(section: String) -> Dictionary:
	var out := {}
	for key in DebugState.keys(section):
		out[key] = DebugState.get_value(section, key)
	return out


func _restore_state(section: String, values: Dictionary) -> void:
	for key in DebugState.keys(section):
		if not values.has(key):
			DebugState.erase(section, key)
	for key in values:
		DebugState.set_value(section, key, values[key])
