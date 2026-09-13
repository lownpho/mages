extends Node2D
## Development entry for the finite World before it replaces the game's generator: plans the shipped
## World, streams its tiles around a real player and lets you walk it. Normal gameplay still runs
## the existing generator. F toggles fly (fast, through walls; it may outrun streaming), R rerolls
## the seed. `shot=<png>` saves a screenshot once the spawn has streamed in and quits; `at=x,y`
## starts at a tile instead of the spawn. Run:
##   godot --path game res://generation/dev/walk_world.tscn -- [seed=123] [at=40,20] [shot=/tmp/world.png]

const CONTENT := "res://generation/world/"
const PLAYER_SCENE := preload("res://characters/player/player.tscn")
const FLY_SPEED := 480.0

@export var world_seed := 0

var _content: WorldContent
var _graph: WorldGraph
var _player: Node2D
var _flying := false

@onready var _streamer: ChunkStreamer = $WorldRoot/Streamer
@onready var _entities: Node2D = $WorldRoot/Entities
@onready var _label: Label = $HUD/Label


func _ready() -> void:
	_content = ContentLoader.load_content(CONTENT)
	if not _content.is_valid():
		push_error("World content has problems:\n" + _content.report())
		return
	var chosen := DebugState.cli_arg("seed")
	_start(chosen.to_int() if chosen.is_valid_int() else world_seed if world_seed != 0 else randi())


func _start(new_seed: int) -> void:
	world_seed = new_seed
	var started := Time.get_ticks_msec()
	_graph = WorldGraph.build(WorldPlanner.plan(_content, world_seed))
	var planned := Time.get_ticks_msec()
	_streamer.build_world(_graph)
	if _player == null:
		_player = PLAYER_SCENE.instantiate()
		_entities.add_child(_player)
	_player.global_position = _streamer.spawn_position()
	var at := DebugState.cli_arg("at").split(",")
	if at.size() == 2 and at[0].is_valid_int() and at[1].is_valid_int():
		_player.global_position = (Vector2(at[0].to_int(), at[1].to_int()) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
	_streamer.target = _player
	_streamer.prepare()
	print("World seed %d: planned in %d ms, spawn chunks in %d ms" % [world_seed, planned - started, Time.get_ticks_msec() - planned])
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
			_flying = not _flying
			_player.process_mode = Node.PROCESS_MODE_DISABLED if _flying else Node.PROCESS_MODE_INHERIT
		KEY_R:
			_start(randi())
