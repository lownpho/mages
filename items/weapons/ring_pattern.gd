extends FirePattern
class_name RingPattern

@export var num_bullets: int = 6

func get_directions(direction: Vector2) -> Array[Vector2]:
	var dirs: Array[Vector2] = []
	var initial_angle = direction.angle()
	var angle_step = TAU / num_bullets
	for i in range(num_bullets):
		var angle = initial_angle + angle_step * i
		dirs.append(Vector2(cos(angle), sin(angle)))
	return dirs
