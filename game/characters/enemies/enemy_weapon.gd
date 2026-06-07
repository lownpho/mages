extends WeaponNode
class_name EnemyWeapon

func setup_for_enemy(weapon_data: WeaponResource) -> void:
	bullet_collision_layer = GameConstants.LAYER_ENEMY_BULLETS
	setup(weapon_data)
	target_finder = _find_player

# Attempts to fire toward target_position. Returns true if a shot was fired.
func try_fire(from_position: Vector2, target_position: Vector2, skill: int) -> bool:
	if not can_fire:
		return false
	var direction = (target_position - from_position).normalized()
	fire(direction, skill)
	return true

# Returns the player if within weapon range, null otherwise.
func _find_player() -> Node2D:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	var player = players[0]
	# Bullet range is in tiles; convert to pixels to match world distances.
	var range_px = data.bullet_data.range_tiles * GameConstants.PX_PER_TILE
	if player.global_position.distance_squared_to(global_position) > range_px * range_px:
		return null
	return player
