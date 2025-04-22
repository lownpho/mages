extends BaseWeapon

# Someone would argue that this is a RingBulletWeapon with a single bullet
# And they would be right

func fire(direction: Vector2, skill: int) -> void:
	if not can_fire or not bullet_scene:
		return
		
	spawn_bullet(direction, skill)
	can_fire = false
	fire_timer.start()
