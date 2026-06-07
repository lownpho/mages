extends Node2D
class_name WeaponNode

const _BulletScene = preload("res://items/bullets/base_bullet.tscn")

var data: WeaponResource
var can_fire: bool = true
var fire_timer: Timer
var bullet_collision_layer: int = GameConstants.LAYER_PLAYER_BULLETS

# Called to find a homing target before each shot.
# The owner sets this so the weapon stays generic — e.g. the player
# targets the enemy closest to the mouse, while an enemy targets the player.
# Signature: func() -> Node2D (or null for no homing).
var target_finder: Callable

var mana_cost: int:
	get: return data.mana_cost if data else 0

func setup(weapon_data: WeaponResource) -> void:
	data = weapon_data
	fire_timer = Timer.new()
	fire_timer.one_shot = true
	fire_timer.wait_time = data.fire_cooldown
	fire_timer.timeout.connect(func(): can_fire = true)
	add_child(fire_timer)

func update_fire_rate(speed_scale: float) -> void:
	# Guard against a zero/negative speed scale (e.g. speed reduced to 0 by
	# modifiers), which would make wait_time infinite or invalid.
	fire_timer.wait_time = data.fire_cooldown / maxf(speed_scale, 0.01)

func fire(direction: Vector2, skill: int) -> void:
	if not can_fire or not data or not data.bullet_data or not data.fire_pattern:
		return
	# Only look for a target when the weapon actually fires homing bullets.
	var target: Node2D = null
	if target_finder and data.bullet_data.homing:
		target = target_finder.call()
	var dirs := data.fire_pattern.get_directions(direction)
	var offsets := data.fire_pattern.get_offsets(direction)
	for i in dirs.size():
		var lateral: Vector2 = offsets[i] if i < offsets.size() else Vector2.ZERO
		_spawn_bullet(dirs[i], skill, target, lateral)
	can_fire = false
	fire_timer.start()

func _spawn_bullet(direction: Vector2, skill: int, target: Node2D, lateral: Vector2 = Vector2.ZERO) -> void:
	var bullet = _BulletScene.instantiate()
	bullet.data = data.bullet_data
	bullet.collision_layer = bullet_collision_layer
	var offset = randf() * data.fire_pattern.spawn_offset
	bullet.position = global_position + direction * offset + lateral
	bullet.base_direction = direction
	bullet.skill = skill
	bullet.target = target
	get_tree().root.add_child(bullet)
