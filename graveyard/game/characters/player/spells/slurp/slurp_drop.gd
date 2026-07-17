extends Sprite2D

## A drop of drained life: spawns at the enemy and streams into the caster, then frees.
## Curved, slightly randomised flight so a steady drain reads as a swirl of droplets.

@export var travel_time: float = 0.35

var target: Node2D

func _ready() -> void:
	var dest: Vector2 = target.global_position if is_instance_valid(target) else global_position
	# Bow the path sideways so drops arc inward instead of sliding in straight lines.
	var mid := (global_position + dest) * 0.5
	mid += (dest - global_position).orthogonal().normalized() * randf_range(-6.0, 6.0)
	var tween := create_tween()
	tween.tween_method(_arc.bind(global_position, mid, dest), 0.0, 1.0, travel_time)
	tween.tween_callback(queue_free)

func _arc(t: float, a: Vector2, b: Vector2, c: Vector2) -> void:
	global_position = a.lerp(b, t).lerp(b.lerp(c, t), t)
