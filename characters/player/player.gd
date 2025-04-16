extends CharacterBody2D

const SPEED = 80.0

@onready var staff = $Staff
@onready var fsm: FSM = $FSM

func _ready() -> void:
	# Connect to state signals
	var idle_state = $FSM/Idle
	idle_state.on_physics_update.connect(_on_idle_physics_update)
	
	var move_state = $FSM/Move
	move_state.on_physics_update.connect(_on_move_physics_update)

func get_input_direction() -> Vector2:
	var direction_x := Input.get_axis("left", "right")
	var direction_y := Input.get_axis("up", "down")
	return Vector2(direction_x, direction_y).normalized()

func _on_idle_physics_update(delta: float) -> void:
	var direction = get_input_direction()
	
	if direction != Vector2.ZERO:
		# I really don't like that this is hardcoded but for now it is what it is
		fsm.transition_to("Move")
		return
		
	# This is a workaround for the fact that move_and_slide() doesn't stop the character
	velocity.x = move_toward(velocity.x, 0, SPEED)
	velocity.y = move_toward(velocity.y, 0, SPEED)
	move_and_slide()
	
	_handle_staff_input()

func _on_move_physics_update(delta: float) -> void:
	var direction = get_input_direction()
	
	if direction == Vector2.ZERO:
		# See comment in _idle_physics_update
		fsm.transition_to("Idle")
		return
		
	velocity = direction * SPEED
	move_and_slide()

	GlobalEvent.emit_signal("player_position_changed", position)
	
	_handle_staff_input()

func _handle_staff_input() -> void:
	if Input.is_action_pressed("staff"):
		var mouse_position = get_global_mouse_position()
		var fire_direction = (mouse_position - position).normalized()
		staff.fire(fire_direction)
