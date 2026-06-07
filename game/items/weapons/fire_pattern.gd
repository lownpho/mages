extends Resource
class_name FirePattern

## Random offset applied to each bullet's spawn position along its direction.
@export var spawn_offset: float = 0.0

func get_directions(direction: Vector2) -> Array[Vector2]:
	return [direction]

## Per-bullet lateral spawn offsets (world space), paired by index with
## get_directions(). Lets a pattern spread bullets sideways without changing
## their travel direction (e.g. parallel shots). Empty means no lateral offset.
func get_offsets(_direction: Vector2) -> Array[Vector2]:
	return []
