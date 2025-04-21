extends CharacterBody2D

@export var max_health: int = 100  # Maximum health
var health: int  # Current health
@export var speed: float = 16.0

@onready var hurtbox = $Hurtbox
@onready var fsm: FSM = $FSM
@onready var detect_probe = $DetectProbe
@onready var chase_probe = $ChaseProbe
@onready var attack_probe = $AttackProbe
@onready var weapon = $Weapon

var player_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	health = max_health 
	hurtbox.hurt.connect(_on_hurt)

	GlobalEvent.connect("player_position_changed", _on_player_position_changed)

	var idle_state = $FSM/Idle
	idle_state.on_enter.connect(_on_idle_enter)
	idle_state.on_exit.connect(_on_idle_exit)
	idle_state.on_physics_update.connect(_on_idle_physics_update)
	var chase_state = $FSM/Chase
	chase_state.on_enter.connect(_on_chase_enter)
	chase_state.on_exit.connect(_on_chase_exit)
	chase_state.on_physics_update.connect(_on_chase_physics_update)
	var attack_state = $FSM/Attack
	attack_state.on_physics_update.connect(_on_attack_physics_update)
	attack_state.on_enter.connect(_on_attack_enter)
	attack_state.on_exit.connect(_on_attack_exit)

	# FSM started here to avoid missing the first enter call
	$FSM.start()

func _on_idle_enter() -> void:
	detect_probe.enabled = true

func _on_idle_exit() -> void:
	detect_probe.enabled = false

func _on_idle_physics_update(_delta: float) -> void:
	detect_probe.look_at(player_position)

	var detect_collider = detect_probe.get_collider()
	if detect_collider and detect_collider.name == "Player":
		fsm.transition_to("Chase")

func _on_chase_enter() -> void:
	chase_probe.enabled = true
	attack_probe.enabled = true

func _on_chase_exit() -> void:
	chase_probe.enabled = false
	attack_probe.enabled = false

func _on_chase_physics_update(_delta: float) -> void:
	var player_direction = player_position - global_position
	
	chase_probe.look_at(player_position)
	attack_probe.look_at(player_position)

	var attack_collider = attack_probe.get_collider()
	var chase_collider = chase_probe.get_collider()
	if attack_collider and attack_collider.name == "Player":
		fsm.transition_to("Attack")
	elif chase_collider and chase_collider.name == "Player":
		velocity = player_direction.normalized() * speed
	else:
		fsm.transition_to("Idle")
	move_and_slide()

func _on_attack_enter() -> void:
	attack_probe.enabled = true

func _on_attack_exit() -> void:
	attack_probe.enabled = false

func _on_attack_physics_update(_delta: float) -> void:
	attack_probe.look_at(player_position)

	var attack_collider = attack_probe.get_collider()
	if attack_collider and attack_collider.name == "Player":
		var player_direction = (player_position - global_position).normalized()
		weapon.fire(player_direction)
	else:
		fsm.transition_to("Chase")

func _on_hurt(damage: int) -> void:
	health -= damage
	print(name, "hurt: ", damage, " remaining health: ", health)
	
	if health <= 0:
		die()

func _on_player_position_changed(pos: Vector2) -> void:
	player_position = pos

func die() -> void:
	queue_free()  # Remove enemy from scene
