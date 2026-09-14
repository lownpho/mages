extends Node2D

## The Run's World: plans the World for the Run's seed, streams its tiles, encounters and
## Objects around the player and keeps the Run saved through GameState. New reuses the title
## backdrop's plan when it has one; Continue plans the saved seed and restores the Run's records
## before anything streams in. In non-web debug builds Tab opens the World debug layer, which the
## Web export leaves out.

## Every tier-1 spell a run may open with, dropped next to the player on a brand-new run —
## the whole starter loadout, no tutorial. Offensive spells only: the tier-1 summons and Heal
## are long-cooldown support, and a run that opened on a hand of them would have nothing to
## kill the first room with.
const STARTER_POOL: Array[Resource] = [
	preload("res://characters/player/spells/pew/pew1.tres"),
	preload("res://characters/player/spells/blam/blam1.tres"),
	preload("res://characters/player/spells/snipe/snipe1.tres"),
	preload("res://characters/player/spells/ring/ring1.tres"),
	preload("res://characters/player/spells/fireball/fireball1.tres"),
	preload("res://characters/player/spells/zaap/zaap1.tres"),
]

## How many of the pool a fresh run is handed — one per cast button. Restates
## GlobalInventory.SPELL_SLOTS because an autoload's constants aren't reachable from a const.
const STARTER_COUNT := 4

## How long Continue builds the discovered Rooms' interiors nearest the player behind the loading
## frame: what the 2 s web startup budget leaves after planning and the spawn's chunks, a third of it
## on desktop. The rest fill in as Map views draw them.
const CONTINUE_INTERIORS_WEB_USEC := 450_000
const CONTINUE_INTERIORS_DESKTOP_USEC := 150_000

const FLY_SPEED := 480.0

## Used when a World is launched without a Run seed (straight from the editor); 0 rolls one.
@export var world_seed := 0
## The World content to plan. Tests walk the small fixture World.
@export_dir var content_root := "res://generation/world/"

var _content: WorldContent
var _graph: WorldGraph
var _encounters: WorldEncounters
var _flying := false
var _debug_layer: Node = null
var _player_collision_mask := 1
var _build_timings := {"plan_ms": 0.0, "graphs_ms": 0.0, "spawn_ms": 0.0, "total_ms": 0.0}

@onready var _streamer: ChunkStreamer = $WorldRoot/Streamer
## Where the debug layer places enemies.
@warning_ignore("unused_private_class_variable")
@onready var _entities: Node2D = $WorldRoot/Entities
@onready var _player: CharacterBody2D = $WorldRoot/Entities/Player
@onready var _encounter_spawner: EncounterSpawner = $EncounterSpawner
@onready var _object_spawner: ObjectSpawner = $ObjectSpawner


func _ready() -> void:
	_player_collision_mask = _player.collision_mask
	var continuing := GameState.continuing_run()
	var fresh := GameState.fresh_start
	var planned := GameState.take_planned_world()
	if planned != null:
		_content = planned.plan.content
	else:
		_content = ContentLoader.load_content(content_root)
		if not _content.is_valid():
			push_error("World content has problems:\n" + _content.report())
			return
	if GameState.active_seed == 0:
		var chosen := GameState.take_cli_seed()
		GameState.active_seed = chosen if chosen != 0 else world_seed if world_seed != 0 else maxi(randi(), 1)
	_start(GameState.active_seed, planned)
	# Spawn buffer: enemies near the spawn can't chip the player before they've taken control
	# (Continue resumes mid-World, so it wants the grace too).
	_player.grant_spawn_grace()
	if GameState.fresh_start:
		GameState.fresh_start = false
		_drop_starter_gear()
	# Keep this a dynamic dependency: the Web export excludes debug/*.
	if OS.is_debug_build() and not OS.has_feature("web"):
		var debug_script := load("res://debug/world/world_debug_layer.gd") as Script
		if debug_script != null:
			_debug_layer = debug_script.new()
			add_child(_debug_layer)
			# A Run's inventory is its own; only a World launched outside one gets the debug loadout.
			_debug_layer.configure(self, not continuing and not fresh)


## Builds the World for a seed, from the given plan when New reuses one. When a Continue is pending
## its records go in before anything streams: defeats and Object states before their chunks spawn,
## the player at the saved spot with the saved health.
func _start(new_seed: int, planned: WorldGraph) -> void:
	world_seed = new_seed
	var started := Time.get_ticks_msec()
	var graph := planned
	var planned_at := started
	if graph == null:
		var world_plan := WorldPlanner.plan(_content, world_seed)
		planned_at = Time.get_ticks_msec()
		graph = WorldGraph.generate(_content, world_seed, world_plan)
		if graph == null:
			return
	# A seed that built no World was rerolled; the Run keeps the seed that built so Continue plans it.
	world_seed = graph.plan.world_seed
	GameState.active_seed = world_seed
	_graph = graph
	var graphed := Time.get_ticks_msec()
	_streamer.build_world(_graph)
	_encounters = WorldEncounters.new(_graph, _streamer.interiors)
	_encounter_spawner.build_world(_encounters, GameState.take_run_defeats())
	_object_spawner.restore_states(GameState.take_object_states())
	_object_spawner.build_world(WorldObjects.new(_graph))
	_player.global_position = _streamer.spawn_position()
	if GameState.has_pending_position:
		# Same-version development saves may predate a content edit, so a spot now in rock snaps to floor.
		_player.global_position = GameState.pending_player_position
		var saved_tile := Vector2i((_player.global_position / GameConstants.PX_PER_TILE).floor())
		if _streamer.interiors.class_at(saved_tile) != WorldInteriors.FLOOR:
			_player.global_position = (Vector2(_nearest_floor(saved_tile)) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
		GameState.has_pending_position = false
	if GameState.pending_player_health > 0:
		_player.health = mini(GameState.pending_player_health, _player.max_health)
		GameState.pending_player_health = 0
		GlobalEvent.player_health_changed.emit(_player.health)
	_streamer.target = _player
	var streaming := Time.get_ticks_msec()
	_streamer.prepare()
	var streamed := Time.get_ticks_msec()
	GlobalMap.rebuild(_streamer, _encounter_spawner.defeats.defeated)
	GlobalMap.active.prepare_discovered(Vector2i((_player.global_position / GameConstants.PX_PER_TILE).floor()),
			CONTINUE_INTERIORS_WEB_USEC if OS.has_feature("web") else CONTINUE_INTERIORS_DESKTOP_USEC)
	var mapped := Time.get_ticks_msec()
	# Entering the World commits the Run to the save and arms autosave.
	GameState.track_player(_player)
	GameState.track_world(_encounter_spawner, _object_spawner)
	GameState.persist()
	var finished := Time.get_ticks_msec()
	_build_timings = {"plan_ms": planned_at - started, "graphs_ms": graphed - planned_at,
			"spawn_ms": finished - graphed, "total_ms": finished - started, "setup_ms": streaming - graphed,
			"stream_ms": streamed - streaming, "map_ms": mapped - streamed, "save_ms": finished - mapped}
	print("World seed %d: plan %d ms, graphs %d ms, spawn %d ms (setup %d, stream %d, map %d, save %d)%s" % [world_seed,
			planned_at - started, graphed - planned_at, finished - graphed, streaming - graphed, streamed - streaming,
			mapped - streamed, finished - mapped, " (plan reused)" if planned != null else ""])


func _process(delta: float) -> void:
	if _flying:
		var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		_player.global_position += direction * FLY_SPEED * delta


## Called by the debug layer after it has selectively rebuilt the graph. A new Run (a reseed) starts
## at spawn with no defeats or Object state; a knob rebuild or content reload keeps them, as keys
## follow place.
func _apply_debug_graph(next_graph: WorldGraph, invalidated_biomes: Dictionary[StringName, bool],
		plan_changed: bool, new_run: bool) -> void:
	_graph = next_graph
	world_seed = next_graph.plan.world_seed
	GameState.active_seed = world_seed
	_streamer.rebuild_world(next_graph, invalidated_biomes, plan_changed)
	_encounters = WorldEncounters.new(_graph, _streamer.interiors)
	_encounter_spawner.build_world(_encounters, RunDefeats.new() if new_run else null)
	_object_spawner.build_world(WorldObjects.new(_graph), new_run)
	if new_run:
		_player.global_position = _streamer.spawn_position()
	else:
		var tile := Vector2i((_player.global_position / GameConstants.PX_PER_TILE).floor())
		_player.global_position = (Vector2(_nearest_floor(tile)) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
	_streamer.target = _player
	_streamer.prepare()
	GlobalMap.rebuild(_streamer, _encounter_spawner.defeats.defeated, not new_run)


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
	_player.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	_player.collision_mask = 0 if on else _player_collision_mask
	if on:
		_player.remove_from_group("player")
	elif not _player.is_in_group("player"):
		_player.add_to_group("player")


# Drop the starter spells beside the player, using the same loot_dropped path enemies
# use (GlobalPickups makes the pickups). The hand is STARTER_COUNT distinct spells drawn
# from STARTER_POOL — distinct because one tier per spell is all the row would hold anyway.
func _drop_starter_gear() -> void:
	var origin := _player.global_position
	var hand := roll_starter_hand()
	for i in hand.size():
		var angle := TAU * i / hand.size()
		GlobalEvent.loot_dropped.emit(hand[i], origin + Vector2(20, 0).rotated(angle))

# STARTER_COUNT spells picked from the pool without repeats: shuffle a copy and take the
# front of it, so the draw stays uniform and can never hand out the same spell twice.
# Static because the tutorial arms the player from the same pool (see tutorial.gd).
static func roll_starter_hand() -> Array[Resource]:
	var pool := STARTER_POOL.duplicate()
	pool.shuffle()
	return pool.slice(0, min(STARTER_COUNT, pool.size()))
