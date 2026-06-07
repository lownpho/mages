extends CharacterBody2D
class_name BaseBullet

## All bullet stats are read from this resource — the single source of truth.
## Set by WeaponNode before the bullet enters the tree.
var data: BulletResource
var base_direction: Vector2 = Vector2.UP
var target: Node2D
var skill: int = 0

var lifetime_timer: Timer

func _speed() -> float:
	return data.speed_tiles * GameConstants.PX_PER_TILE

func _ready() -> void:
	# A bullet with no forward speed or no range can't travel — it would also make
	# the lifetime (range / speed) zero or divide by zero, which is an invalid
	# Timer.wait_time. Discard it rather than spawn a degenerate bullet.
	var lifetime := float(data.range_tiles) / data.speed_tiles if data.speed_tiles > 0 else 0.0
	if lifetime <= 0.0:
		queue_free()
		return

	lifetime_timer = Timer.new()
	lifetime_timer.one_shot = true
	lifetime_timer.wait_time = lifetime
	lifetime_timer.autostart = true
	lifetime_timer.timeout.connect(queue_free)
	add_child(lifetime_timer)

	velocity = base_direction * _speed()
	rotation = velocity.angle() + PI / 2

	if data.icon:
		$Sprite2D.texture = data.icon

func _physics_process(delta: float) -> void:
	if data.homing and is_instance_valid(target):
		var speed := _speed()
		var desired := global_position.direction_to(target.global_position)
		velocity = velocity.lerp(desired * speed, data.homing_weight * delta).normalized() * speed
		rotation = velocity.angle() + PI / 2

	if move_and_collide(velocity * delta):
		queue_free()

func get_damage() -> int:
	return round(data.base_damage + skill * data.skill_scaling)

func reached_hurtbox() -> void:
	queue_free()
