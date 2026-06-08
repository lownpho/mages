extends CharacterBody2D

@export var max_health: int = 100
var health: int
@export var skill: int = 0
@export var speed: float = 16.0
@export var weave_frequency: float = 2.0 # Sideways oscillation rate of the S-pattern.
@export var weave_amplitude: float = 1.3 # Sideways sway strength relative to forward speed.

@export var wander_speed: float = 14.0 ## Speed while strolling in the Wander state.

# Drives the S-pattern weave during chase.
var _weave_time: float = 0.0
var _weave_phase: float = 0.0
var _weave_retarget: float = 0.0

var _wander_dir: Vector2 = Vector2.ZERO
var _idle_timer: Timer
var _wander_timer: Timer

@onready var hurtbox = $Hurtbox
@onready var fsm: FSM = $FSM
@onready var detect_probe = $DetectProbe
@onready var chase_probe = $ChaseProbe
@onready var attack_probe = $AttackProbe
@export var weapon_data: WeaponResource
@onready var weapon: EnemyWeapon = $Weapon

func _ready() -> void:
	health = max_health
	hurtbox.hurt.connect(_on_hurt)
	if weapon_data:
		weapon.setup_for_enemy(weapon_data)

	var idle_state = $FSM/Idle
	idle_state.on_enter.connect(_on_idle_enter)
	idle_state.on_exit.connect(_on_idle_exit)
	idle_state.on_physics_update.connect(_on_idle_physics_update)
	var wander_state = $FSM/Wander
	wander_state.on_enter.connect(_on_wander_enter)
	wander_state.on_exit.connect(_on_wander_exit)
	wander_state.on_physics_update.connect(_on_wander_physics_update)
	var chase_state = $FSM/Chase
	chase_state.on_enter.connect(_on_chase_enter)
	chase_state.on_exit.connect(_on_chase_exit)
	chase_state.on_physics_update.connect(_on_chase_physics_update)
	var attack_state = $FSM/Attack
	attack_state.on_physics_update.connect(_on_attack_physics_update)
	attack_state.on_enter.connect(_on_attack_enter)
	attack_state.on_exit.connect(_on_attack_exit)

	_idle_timer = _make_timer(func(): fsm.transition_to("Wander"))
	_wander_timer = _make_timer(func(): fsm.transition_to("Idle"))

	# FSM started here to avoid missing the first enter call
	$FSM.start()

func _make_timer(on_timeout: Callable) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.timeout.connect(on_timeout)
	add_child(timer)
	return timer

func _get_player_position() -> Vector2:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return global_position
	return players[0].global_position

func _detect_player() -> bool:
	detect_probe.look_at(_get_player_position())
	var detect_collider = detect_probe.get_collider()
	if detect_collider and detect_collider.is_in_group("player"):
		fsm.transition_to("Chase")
		return true
	return false

func _on_idle_enter() -> void:
	detect_probe.enabled = true
	velocity = Vector2.ZERO
	_idle_timer.start(randf_range(1.5, 4.0))
	$AnimatedSprite2D.play("idle")

func _on_idle_exit() -> void:
	detect_probe.enabled = false
	_idle_timer.stop()

func _on_idle_physics_update(_delta: float) -> void:
	_detect_player()

func _on_wander_enter() -> void:
	detect_probe.enabled = true
	_wander_dir = Vector2.from_angle(randf() * TAU)
	_wander_timer.start(randf_range(0.4, 1.2))
	$AnimatedSprite2D.play("run")

func _on_wander_exit() -> void:
	detect_probe.enabled = false
	_wander_timer.stop()

func _on_wander_physics_update(_delta: float) -> void:
	if _detect_player():
		return
	velocity = _wander_dir * wander_speed
	move_and_slide()
	_update_facing(_wander_dir.x)

func _on_chase_enter() -> void:
	chase_probe.enabled = true
	attack_probe.enabled = true
	_weave_time = 0.0
	_weave_retarget = 0.0
	$AnimatedSprite2D.play("run")

func _on_chase_exit() -> void:
	chase_probe.enabled = false
	attack_probe.enabled = false

func _on_chase_physics_update(_delta: float) -> void:
	var player_pos = _get_player_position()
	var player_direction = player_pos - global_position

	chase_probe.look_at(player_pos)
	attack_probe.look_at(player_pos)
	_update_facing(player_direction.x)

	var attack_collider = attack_probe.get_collider()
	var chase_collider = chase_probe.get_collider()
	if attack_collider and attack_collider.is_in_group("player"):
		fsm.transition_to("Attack")
	elif chase_collider and chase_collider.is_in_group("player"):
		velocity = _weave_velocity(player_direction, _delta)
		move_and_slide()
	else:
		fsm.transition_to("Idle")

# Builds an S-pattern velocity: forward toward the player plus a perpendicular
# sine sway. The phase is re-rolled at random intervals so the snake darts
# quick and unpredictably instead of tracing a clean, readable sine.
func _weave_velocity(to_player: Vector2, delta: float) -> Vector2:
	_weave_time += delta
	_weave_retarget -= delta
	if _weave_retarget <= 0.0:
		_weave_retarget = randf_range(0.3, 0.9)
		_weave_phase = randf_range(-PI, PI)
	var forward := to_player.normalized()
	var perp := Vector2(-forward.y, forward.x)
	var sway := sin(_weave_time * weave_frequency + _weave_phase) * weave_amplitude
	return (forward + perp * sway) * speed

func _on_attack_enter() -> void:
	$AnimatedSprite2D.play("idle")
	attack_probe.enabled = true

func _on_attack_exit() -> void:
	attack_probe.enabled = false

func _on_attack_physics_update(_delta: float) -> void:
	var player_pos = _get_player_position()
	attack_probe.look_at(player_pos)
	_update_facing(player_pos.x - global_position.x)

	var attack_collider = attack_probe.get_collider()
	if attack_collider and attack_collider.is_in_group("player"):
		weapon.try_fire(global_position, player_pos, skill)
	else:
		fsm.transition_to("Chase")

# Faces the sprite toward horizontal movement/target. Sprites default to facing
# right, so flip when the target is to the left. Ignores near-vertical headings
# to avoid flicker. Uses the heading (not the weaving velocity) so the S-pattern
# sway doesn't cause rapid flip jitter.
func _update_facing(dir_x: float) -> void:
	if absf(dir_x) > 0.01:
		$AnimatedSprite2D.flip_h = dir_x < 0.0

func die() -> void:
	queue_free()

func _on_hurt(damage: int) -> void:
	health -= damage

	if health <= 0:
		die()
