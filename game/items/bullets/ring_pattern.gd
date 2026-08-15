extends FirePattern
class_name RingPattern

@export var num_bullets: int = 6

func get_directions(direction: Vector2) -> Array[Vector2]:
	var dirs: Array[Vector2] = []
	var initial_angle = direction.angle()
	for i in range(num_bullets):
		dirs.append(Vector2.from_angle(initial_angle + TAU / num_bullets * i))
	return dirs
