extends FirePattern
class_name ShotgunPattern

@export var num_pellets: int = 3
@export var spread_angle: float = 20.0 ## Cone width in degrees.

func get_directions(direction: Vector2) -> Array[Vector2]:
	var dirs: Array[Vector2] = []
	var base_angle = direction.angle()
	var spread_tick = deg_to_rad(spread_angle) / (num_pellets - 1)
	var start_spread = -deg_to_rad(spread_angle) / 2
	for i in range(num_pellets):
		var offset = start_spread + i * spread_tick
		dirs.append(Vector2.from_angle(base_angle + offset))
	return dirs
