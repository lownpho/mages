extends FirePattern
class_name ParallelPattern

## Fires bullets travelling in the same direction, spread out side-by-side
## (perpendicular to the aim). The snake's twin shot uses num_bullets = 2.
@export var num_bullets: int = 2
@export var separation: float = 4.0 ## Perpendicular gap between adjacent bullets, in pixels.

func get_directions(direction: Vector2) -> Array[Vector2]:
	var dirs: Array[Vector2] = []
	for i in range(num_bullets):
		dirs.append(direction)
	return dirs

func get_offsets(direction: Vector2) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	var perp := Vector2(-direction.y, direction.x).normalized()
	# Center the spread around the firing axis.
	var start := -(num_bullets - 1) / 2.0
	for i in range(num_bullets):
		offsets.append(perp * (start + i) * separation)
	return offsets
