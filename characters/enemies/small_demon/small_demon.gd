extends CharacterBody2D

@export var max_health: int = 100 
var health: int
@export var skill: int = 0
@export var speed: float = 16.0

@onready var hurtbox = $Hurtbox
@onready var fsm: FSM = $FSM
@onready var detect_probe = $DetectProbe
@onready var chase_probe = $ChaseProbe
@onready var attack_probe = $AttackProbe
@export var weapon_data: WeaponResource
@onready var weapon: WeaponNode = $Weapon

func _ready() -> void:
	health = max_health
	hurtbox.hurt.connect(_on_hurt)
	if weapon_data:
		weapon.setup(weapon_data)

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

func _get_player_position() -> Vector2:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return global_position
	return players[0].global_position

func _on_idle_enter() -> void:
	detect_probe.enabled = true

func _on_idle_exit() -> void:
	detect_probe.enabled = false

func _on_idle_physics_update(_delta: float) -> void:
	detect_probe.look_at(_get_player_position())

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
	var player_pos = _get_player_position()
	var player_direction = player_pos - global_position

	chase_probe.look_at(player_pos)
	attack_probe.look_at(player_pos)

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
	attack_probe.look_at(_get_player_position())

	var attack_collider = attack_probe.get_collider()
	if attack_collider and attack_collider.name == "Player" and weapon.can_fire:
		var player_direction = (_get_player_position() - global_position).normalized()
		weapon.fire(player_direction, skill)
	else:
		fsm.transition_to("Chase")

func die() -> void:
	queue_free()

func _on_hurt(damage: int) -> void:
	health -= damage
	
	if health <= 0:
		die()
