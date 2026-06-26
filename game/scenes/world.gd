extends Node2D

## Untick to leave the scene empty instead of streaming a world into it.
@export var generate_world := true
@export var world_seed := 0          # 0 = random each run, captured once for the session

@onready var _streamer: ChunkStreamer = $ChunkStreamer

func _ready() -> void:
	if not generate_world:
		return
	# Player starts at world origin; the streamer primes the chunks around it from here.
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = Vector2.ZERO
	_streamer.init(world_seed if world_seed != 0 else randi())
