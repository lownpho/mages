extends CharacterBody2D

@export var max_health: int = 100
@export var max_mana: int = 10
@export var skill: int = 25
@export var speed: int = 80
@export var focus_mana_recover: int = 1

@onready var hurtbox = $Hurtbox
@onready var weapon = $Weapon
@onready var fsm: FSM = $FSM

var health: int
var mana: int
var focus_delay: float = 1.0
var is_recovering_mana: bool = false

func _ready() -> void:
	var idle_state = $FSM/Idle
	idle_state.on_physics_update.connect(_on_idle_physics_update)
	var move_state = $FSM/Move
	move_state.on_physics_update.connect(_on_move_physics_update)
	var focus_state = $FSM/Focus
	focus_state.on_physics_update.connect(_on_focus_physics_update)
	focus_state.on_enter.connect(_on_focus_enter)

	hurtbox.hurt.connect(_on_hurt)
	health = max_health
	mana = max_mana

	GlobalEvent.emit_signal("player_max_health_changed", max_health)
	GlobalEvent.emit_signal("player_health_changed", health)
	GlobalEvent.emit_signal("player_max_mana_changed", max_mana)
	GlobalEvent.emit_signal("player_mana_changed", mana)
	GlobalEvent.emit_signal("player_skill_changed", skill)
	GlobalEvent.emit_signal("player_speed_changed", speed)

func get_input_direction() -> Vector2:
	var direction_x := Input.get_axis("left", "right")
	var direction_y := Input.get_axis("up", "down")
	return Vector2(direction_x, direction_y).normalized()

func _handle_weapon_input() -> void:
	if Input.is_action_pressed("weapon") and mana > 0 and weapon.can_fire:
		var mouse_position = get_global_mouse_position()
		var fire_direction = (mouse_position - position).normalized()

		mana -= weapon.mana_cost
		GlobalEvent.emit_signal("player_mana_changed", mana)
		weapon.fire(fire_direction, skill)

func _on_idle_physics_update(_delta: float) -> void:
	if Input.is_action_just_pressed("focus"):
		fsm.transition_to("Focus")
		return

	var direction = get_input_direction()
	
	if direction != Vector2.ZERO:
		# I really don't like that this is hardcoded but for now it is what it is
		fsm.transition_to("Move")
		return
		
	# This is a workaround for the fact that move_and_slide() doesn't stop the character
	velocity.x = move_toward(velocity.x, 0, speed)
	velocity.y = move_toward(velocity.y, 0, speed)
	move_and_slide()
	
	_handle_weapon_input()

func _on_move_physics_update(_delta: float) -> void:
	var direction = get_input_direction()
	
	if direction == Vector2.ZERO:
		# See comment in _idle_physics_update
		fsm.transition_to("Idle")
		return
		
	velocity = direction * speed
	move_and_slide()

	GlobalEvent.emit_signal("player_position_changed", position)
	
	_handle_weapon_input()

func _recover_mana() -> void:
	mana = min(mana + focus_mana_recover, max_mana)
	GlobalEvent.emit_signal("player_mana_changed", mana)
	if Input.is_action_pressed("focus"):
		var timer = get_tree().create_timer(1.0)
		timer.timeout.connect(_recover_mana)

func _on_focus_enter() -> void:
	var timer = get_tree().create_timer(focus_delay)
	timer.timeout.connect(_recover_mana)

func _on_focus_physics_update(_delta: float) -> void:
	if Input.is_action_just_released("focus"):
		fsm.transition_to("Idle")

func _die() -> void:
	queue_free()

func _on_hurt(damage: int) -> void:
	health -= damage
	GlobalEvent.emit_signal("player_health_changed", health)
	
	if health <= 0:
		_die()
