extends Node2D

## Untick to leave the scene empty instead of streaming a world into it.
@export var generate_world := true
@export var world_seed := 0          # 0 = random each run, captured once for the session

@onready var _streamer: WorldStreamer = $WorldRoot/WorldStreamer
@onready var _player: Node2D = $WorldRoot/Entities/Player

func _ready() -> void:
	if not generate_world:
		return
	_streamer.build_world(world_seed if world_seed != 0 else randi())
	# Deterministic spawn: the fallback-type room nearest the starting biome's center.
	_player.global_position = _streamer.find_spawn_position()
	# Relay onto the game-wide bus: worldgen stays self-contained, game systems
	# (bestiary) listen on GlobalEvent.
	_streamer.biome_entered.connect(GlobalEvent.biome_entered.emit)
	_streamer.target = _player
	GlobalEvent.world_ready.emit(_streamer)
