extends WeaponNode
class_name EnemyWeapon

func setup_for_enemy(weapon_data: WeaponResource) -> void:
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
	if player.global_position.distance_squared_to(global_position) > _homing_range * _homing_range:
		return null
	return player
