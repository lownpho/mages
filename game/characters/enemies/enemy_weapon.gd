extends WeaponNode
class_name EnemyWeapon

# Which groups this weapon's homing/auto-aim hunts, and the bullet layer it fires
# on — both inherited from the owning Enemy so the same weapon serves enemies
# (enemy bullets aimed at the player) and summons (player bullets aimed at enemies).
var _target_groups: Array[String] = ["player"]

func setup_for_enemy(weapon_data: WeaponResource) -> void:
	var owner_enemy := _owner_enemy()
	if owner_enemy:
		bullet_collision_layer = owner_enemy.bullet_collision_layer
		_target_groups = owner_enemy.target_groups
	setup(weapon_data)
	target_finder = _find_target

# Attempts to fire toward target_position. Returns true if a shot was fired.
func try_fire(from_position: Vector2, target_position: Vector2, skill: int) -> bool:
	if not can_fire:
		return false
	var direction = (target_position - from_position).normalized()
	fire(direction, skill)
	return true

func _owner_enemy() -> Enemy:
	var node: Node = get_parent()
	while node and not (node is Enemy):
		node = node.get_parent()
	return node as Enemy

# Returns the nearest target within weapon range, null otherwise.
func _find_target() -> Node2D:
	# Bullet range is in tiles; convert to pixels to match world distances.
	var range_px = data.bullet_data.range_tiles * GameConstants.PX_PER_TILE
	var range_sq = range_px * range_px
	var nearest: Node2D = null
	var best := INF
	for group in _target_groups:
		for node in get_tree().get_nodes_in_group(group):
			var dist: float = node.global_position.distance_squared_to(global_position)
			if dist <= range_sq and dist < best:
				best = dist
				nearest = node
	return nearest
