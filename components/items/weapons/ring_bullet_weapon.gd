extends BaseWeapon

@export var num_bullets: int = 8

func fire(direction: Vector2, skill: int) -> void:
	if not can_fire or not bullet_scene:
		return
	
	var initial_angle = direction.angle()
	var angle_step = 2 * PI / num_bullets
	for i in range(num_bullets):
		var angle = initial_angle + angle_step * i
		var bullet_direction = Vector2(cos(angle), sin(angle))
		spawn_bullet(bullet_direction, skill)

	can_fire = false
	fire_timer.start()
