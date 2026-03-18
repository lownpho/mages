extends Node2D
class_name WeaponNode

var data: WeaponResource
var can_fire: bool = true
var fire_timer: Timer

var mana_cost: int:
	get: return data.mana_cost if data else 0

func setup(weapon_data: WeaponResource) -> void:
	data = weapon_data
	fire_timer = Timer.new()
	fire_timer.one_shot = true
	fire_timer.wait_time = data.fire_cooldown
	fire_timer.timeout.connect(func(): can_fire = true)
	add_child(fire_timer)

func fire(direction: Vector2, skill: int) -> void:
	if not can_fire or not data or not data.bullet_scene:
		return
	match data.fire_pattern:
		WeaponResource.FirePattern.SINGLE:
			_spawn_bullet(direction, skill)
		WeaponResource.FirePattern.RING:
			_fire_ring(direction, skill)
	can_fire = false
	fire_timer.start()

func _fire_ring(direction: Vector2, skill: int) -> void:
	var initial_angle = direction.angle()
	var angle_step = 2 * PI / data.num_bullets
	for i in range(data.num_bullets):
		var angle = initial_angle + angle_step * i
		var bullet_direction = Vector2(cos(angle), sin(angle))
		_spawn_bullet(bullet_direction, skill)

func _spawn_bullet(direction: Vector2, skill: int) -> void:
	var bullet = data.bullet_scene.instantiate()
	bullet.position = global_position
	bullet.base_direction = direction
	bullet.skill = skill
	get_tree().root.add_child(bullet)
