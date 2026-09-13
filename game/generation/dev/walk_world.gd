extends Node2D
## Development entry for the finite World before it replaces the game's generator: plans the shipped
## World, streams its tiles around a real player and lets you walk it. Normal gameplay still runs
## the existing generator. In debug builds Tab opens the integrated paused World tool; F toggles
## fly (fast, through walls; it may outrun streaming), and R rerolls. `shot=<png>` saves a screenshot
## once the spawn has streamed in and quits; `at=x,y`
## starts at a tile instead of the spawn. Run:
##   godot --path game res://generation/dev/walk_world.tscn -- [seed=123] [at=40,20] [shot=/tmp/world.png]

const CONTENT := "res://generation/world/"
const PLAYER_SCENE := preload("res://characters/player/player.tscn")
const FLY_SPEED := 480.0

@export var world_seed := 0

var _content: WorldContent
var _graph: WorldGraph
var _encounters: WorldEncounters
var _player: CharacterBody2D
var _flying := false
var _debug_layer: Node = null
var _player_collision_mask := 1
var _build_timings := {"plan_ms": 0.0, "graphs_ms": 0.0, "spawn_ms": 0.0, "total_ms": 0.0}

@onready var _streamer: ChunkStreamer = $WorldRoot/Streamer
@onready var _entities: Node2D = $WorldRoot/Entities
@onready var _encounter_spawner: EncounterSpawner = $EncounterSpawner
@onready var _label: Label = $HUD/Label


func _ready() -> void:
	_content = ContentLoader.load_content(CONTENT)
	if not _content.is_valid():
		push_error("World content has problems:\n" + _content.report())
		return
	var chosen := DebugState.cli_arg("seed")
	_start(chosen.to_int() if chosen.is_valid_int() else world_seed if world_seed != 0 else randi())
	# Keep this a dynamic dependency: the Web export excludes debug/*, and the development entry can
	# still be parsed/exported without pulling debug code into the package.
	if OS.is_debug_build() and not OS.has_feature("web"):
		var debug_script := load("res://debug/world/world_debug_layer.gd") as Script
		if debug_script != null:
			_debug_layer = debug_script.new()
			add_child(_debug_layer)
			_debug_layer.configure(self)


func _start(new_seed: int) -> void:
	world_seed = new_seed
	GameState.active_seed = new_seed
	var started := Time.get_ticks_msec()
	var world_plan := WorldPlanner.plan(_content, world_seed)
	var planned := Time.get_ticks_msec()
	_graph = WorldGraph.build(world_plan)
	var graphed := Time.get_ticks_msec()
	_streamer.build_world(_graph)
	_encounters = WorldEncounters.new(_graph, _streamer.interiors)
	_encounter_spawner.build_world(_encounters, RunDefeats.new())
	if _player == null:
		_player = PLAYER_SCENE.instantiate()
		_entities.add_child(_player)
		_player_collision_mask = _player.collision_mask
	_player.global_position = _streamer.spawn_position()
	var at := DebugState.cli_arg("at").split(",")
	if at.size() == 2 and at[0].is_valid_int() and at[1].is_valid_int():
		_player.global_position = (Vector2(at[0].to_int(), at[1].to_int()) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
	_streamer.target = _player
	_streamer.prepare()
	var finished := Time.get_ticks_msec()
	_build_timings = {"plan_ms": planned - started, "graphs_ms": graphed - planned,
			"spawn_ms": finished - graphed, "total_ms": finished - started}
	print("World seed %d: plan %d ms, graphs %d ms, spawn chunks %d ms" % [world_seed,
			planned - started, graphed - planned, finished - graphed])
	var shot := DebugState.cli_arg("shot")
	if shot != "":
		for _frame in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()


func _process(delta: float) -> void:
	if _graph == null:
		return
	if _flying:
		var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		_player.global_position += direction * FLY_SPEED * delta
	var tile := Vector2i((_player.global_position / GameConstants.PX_PER_TILE).floor())
	var room := _streamer.interiors.owner_at(tile)
	var place := "outside the World"
	if room != null:
		place = "%s  %s/%s  %s  Challenge %d" % [room.key(), room.plan.biome, room.plan.zone, room.role_name(), room.plan.challenge]
	_label.text = "seed %d  tile %d,%d  %s\nchunks %d loaded, %d queued, %.2f ms   F fly%s   R reroll" % [world_seed, tile.x, tile.y,
			place, _streamer.loaded_chunks(), _streamer.queued_chunks(), _streamer.last_work_usec / 1000.0, " (on)" if _flying else ""]


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F:
			_set_flying(not _flying)
		KEY_R:
			if _debug_layer != null:
				_debug_layer._reseed(randi())
			else:
				_start(randi())


## Called by the integrated debug layer after it has selectively rebuilt the graph. A new Run (a
## reseed) starts at spawn with no defeats; a knob rebuild keeps them, as keys follow place.
func _apply_debug_graph(next_graph: WorldGraph, invalidated_biomes: Dictionary[StringName, bool],
		plan_changed: bool, new_run: bool) -> void:
	_graph = next_graph
	world_seed = next_graph.plan.world_seed
	GameState.active_seed = world_seed
	_streamer.rebuild_world(next_graph, invalidated_biomes, plan_changed)
	_encounters = WorldEncounters.new(_graph, _streamer.interiors)
	_encounter_spawner.build_world(_encounters, RunDefeats.new() if new_run else null)
	if new_run:
		_player.global_position = _streamer.spawn_position()
	else:
		var tile := Vector2i((_player.global_position / GameConstants.PX_PER_TILE).floor())
		_player.global_position = (Vector2(_nearest_floor(tile)) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
	_streamer.target = _player
	_streamer.prepare()


## Teleports to the requested tile when it is floor, otherwise to its nearest floor. Preparing the
## destination synchronously happens behind the already-paused panel.
func _teleport_to_tile(tile: Vector2i) -> void:
	_player.global_position = (Vector2(_nearest_floor(tile)) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
	_streamer.prepare()


func _nearest_floor(origin: Vector2i) -> Vector2i:
	if _streamer.interiors.class_at(origin) == WorldInteriors.FLOOR:
		return origin
	for radius in range(1, WorldPlan.CELL + 1):
		for x in range(-radius, radius + 1):
			for y in [-radius, radius]:
				var tile := origin + Vector2i(x, y)
				if _streamer.interiors.class_at(tile) == WorldInteriors.FLOOR:
					return tile
		for y in range(-radius + 1, radius):
			for x in [-radius, radius]:
				var tile := origin + Vector2i(x, y)
				if _streamer.interiors.class_at(tile) == WorldInteriors.FLOOR:
					return tile
	return Vector2i((_streamer.spawn_position() / GameConstants.PX_PER_TILE).floor())


## Fly is the real player with physics and casting suspended. Streaming still follows its position;
## removing its target group makes current/future enemy acquisition ignore it.
func _set_flying(on: bool) -> void:
	_flying = on
	if _debug_layer != null:
		DebugState.set_value("world_debug", "fly", on)
	if _player == null:
		return
	_player.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	_player.collision_mask = 0 if on else _player_collision_mask
	if on:
		_player.remove_from_group("player")
	elif not _player.is_in_group("player"):
		_player.add_to_group("player")
