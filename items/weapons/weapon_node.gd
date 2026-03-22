extends Node2D
class_name WeaponNode

const _BaseBulletScene = preload("res://items/bullets/base_bullet.tscn")
const _HomingBulletScene = preload("res://items/bullets/homing_bullet.tscn")

var data: WeaponResource
var can_fire: bool = true
var fire_timer: Timer
var _is_homing: bool = false
var _homing_range: float = 0.0
var bullet_collision_layer: int = 256

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
	_is_homing = data.bullet_data.homing
	_homing_range = data.bullet_data.distance if _is_homing else 0

func fire(direction: Vector2, skill: int) -> void:
	if not can_fire or not data or not data.bullet_data or not data.fire_pattern:
		return
	# Only look for a target when the weapon actually fires homing bullets.
	var target: Node2D = null
	if target_finder and _is_homing:
		target = target_finder.call()
	for dir in data.fire_pattern.get_directions(direction):
		_spawn_bullet(dir, skill, target)
	can_fire = false
	fire_timer.start()

func _spawn_bullet(direction: Vector2, skill: int, target: Node2D) -> void:
	var scene = _HomingBulletScene if _is_homing else _BaseBulletScene
	var bullet = scene.instantiate()
	bullet.base_damage = data.bullet_data.base_damage
	bullet.distance = data.bullet_data.distance
	bullet.speed = data.bullet_data.speed
	bullet.skill_scaling = data.bullet_data.skill_scaling
	bullet.collision_layer = bullet_collision_layer
	var offset = randf() * data.fire_pattern.spawn_offset
	bullet.position = global_position + direction * offset
	bullet.base_direction = direction
	bullet.skill = skill
	if target and bullet is HomingBullet:
		bullet.homing_weight = data.bullet_data.homing_weight
		bullet.target = target
	if data.bullet_data.icon:
		bullet.get_node("Sprite2D").texture = data.bullet_data.icon
	get_tree().root.add_child(bullet)
