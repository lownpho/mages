extends FirePattern
class_name ShotgunPattern

@export var num_pellets: int = 3
@export var spread_angle: float = 20.0 ## Cone width in degrees.

func get_directions(direction: Vector2) -> Array[Vector2]:
	var dirs: Array[Vector2] = []
	var base_angle = direction.angle()
	var half_spread = deg_to_rad(spread_angle) / 2.0
	for i in range(num_pellets):
		var offset = randf_range(-half_spread, half_spread)
		dirs.append(Vector2.from_angle(base_angle + offset))
	return dirs
