extends Camera2D

@export var lookahead_distance: float = 20.0
@export var lookahead_smoothing: float = 4.0

@onready var _target: CharacterBody2D = get_parent()

func _ready() -> void:
	# Read velocity after the player has moved this frame
	process_physics_priority = 500

func _physics_process(delta: float) -> void:
	var desired := _target.velocity.normalized() * lookahead_distance
	var weight := 1.0 - exp(-lookahead_smoothing * delta)
	position = position.lerp(desired, weight)
