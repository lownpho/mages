extends BaseBullet
class_name HomingBullet

@export var homing_weight: float = 5.0

var target: Node2D

func _physics_process(delta: float) -> void:
	if is_instance_valid(target):
		var desired = global_position.direction_to(target.global_position)
		velocity = velocity.lerp(desired * speed, homing_weight * delta).normalized() * speed
	super(delta)
	rotation = velocity.angle() + PI / 2
