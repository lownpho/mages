extends Node2D

## Untick to leave the scene empty instead of streaming a world into it.
@export var generate_world := true
@export var world_seed := 0          # 0 = random each run, captured once for the session

@onready var _streamer: ChunkStreamer = $ChunkStreamer

func _ready() -> void:
	if not generate_world:
		return
	# The streamer positions the player at a validated Glade spawn, then primes chunks around it.
	_streamer.init(world_seed if world_seed != 0 else randi())
