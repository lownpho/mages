extends CharacterBody2D

const SPEED = 80.0

@onready var staff = $Staff

func _physics_process(delta: float) -> void:

	# Is there a better way than poll evey physics frame?
	var direction_x := Input.get_axis("left", "right")
	var direction_y := Input.get_axis("up", "down")
	var direction := Vector2(direction_x, direction_y).normalized()
	if direction != Vector2.ZERO:
		velocity = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.y = move_toward(velocity.y, 0, SPEED)
	
	move_and_slide()

	if Input.is_action_pressed("staff"):
		var mouse_position = get_global_mouse_position()
		var fire_direction = (mouse_position - position).normalized()
		staff.fire(fire_direction)
