extends WeaponNode
class_name PlayerWeapon

var owner_ref: CharacterBody2D
var weapon_input_held: bool = false

func setup_for_player(weapon_data: WeaponResource, player: CharacterBody2D) -> void:
	owner_ref = player
	bullet_collision_layer = GameConstants.LAYER_PLAYER_BULLETS
	setup(weapon_data)
	target_finder = _find_closest_enemy_to_mouse

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("weapon"):
		weapon_input_held = true
	elif event.is_action_released("weapon"):
		weapon_input_held = false

func _physics_process(_delta: float) -> void:
	if not owner_ref or not data:
		return
	if not weapon_input_held or not can_fire:
		return
	if not owner_ref.can_use_weapon:
		return
	if owner_ref.mana < mana_cost:
		return

	var mouse_pos = owner_ref.get_global_mouse_position()
	var direction = (mouse_pos - owner_ref.global_position).normalized()

	owner_ref.mana -= mana_cost
	GlobalEvent.player_mana_changed.emit(owner_ref.mana)
	fire(direction, owner_ref.skill)

# Targets the enemy closest to the mouse cursor within weapon range.
# Returns null if no enemy is in range — the bullet flies straight.
func _find_closest_enemy_to_mouse() -> Node2D:
	var mouse_pos = owner_ref.get_global_mouse_position()
	# Bullet range is in tiles; convert to pixels to match world distances.
	var range_px = data.bullet_data.range_tiles * GameConstants.PX_PER_TILE
	var range_sq = range_px * range_px
	var closest: Node2D = null
	var closest_dist: float = INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		# Must be within range of the shooter, not just close to the cursor.
		if enemy.global_position.distance_squared_to(global_position) > range_sq:
			continue
		var dist = enemy.global_position.distance_squared_to(mouse_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = enemy
	return closest
