extends Node2D

## Untick to leave the scene empty instead of streaming a world into it.
@export var generate_world := true
@export var world_seed := 0          # 0 = random each run, captured once for the session

@onready var _streamer: WorldStreamer = $WorldStreamer
@onready var _player: Node2D = $Entities/Player

func _ready() -> void:
	if not generate_world:
		return
	_streamer.config.prepare()
	_streamer.init(world_seed if world_seed != 0 else randi())
	# Deterministic spawn: the traversal room nearest the glade's center, on a validated tile.
	_player.global_position = _streamer.find_spawn_position()
	_streamer.target = _player
