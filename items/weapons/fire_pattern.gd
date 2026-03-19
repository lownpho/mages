extends Resource
class_name FirePattern

## Random offset applied to each bullet's spawn position along its direction.
@export var spawn_offset: float = 0.0

func get_directions(direction: Vector2) -> Array[Vector2]:
	return [direction]
