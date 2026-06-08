extends CharacterBody2D

@export var max_health: int = 55
var health: int
@export var skill: int = 0

@export var speed: float = 24.0 ## Movement speed while closing to sniping range.
@export var wander_speed: float = 16.0 ## Speed of the occasional idle stroll.
@export var retreat_speed: float = 34.0 ## Fallback speed while cacasbruming rings.

@export var charge_time: float = 0.9 ## Sniper wind-up before each shot.

@export var sniper_weapon: WeaponResource
@export var ring_weapon: WeaponResource

var _charge_timer: Timer
var _wander_dir: Vector2 = Vector2.ZERO
var _idle_timer: Timer
var _wander_timer: Timer

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox = $Hurtbox
@onready var fsm: FSM = $FSM
@onready var detect_probe: RayCast2D = $DetectProbe
@onready var sniper_probe: RayCast2D = $SniperProbe
@onready var close_probe: RayCast2D = $CloseProbe
@onready var sniper_node: EnemyWeapon = $SniperWeapon
@onready var ring_node: EnemyWeapon = $RingWeapon

func _ready() -> void:
	health = max_health
	hurtbox.hurt.connect(_on_hurt)
	if sniper_weapon:
		sniper_node.setup_for_enemy(sniper_weapon)
	if ring_weapon:
		ring_node.setup_for_enemy(ring_weapon)

	var idle_state = $FSM/Idle
	idle_state.on_enter.connect(_on_idle_enter)
	idle_state.on_exit.connect(_on_idle_exit)
	idle_state.on_physics_update.connect(_on_idle_physics_update)
	var wander_state = $FSM/Wander
	wander_state.on_enter.connect(_on_wander_enter)
	wander_state.on_exit.connect(_on_wander_exit)
	wander_state.on_physics_update.connect(_on_wander_physics_update)
	var approach_state = $FSM/Approach
	approach_state.on_enter.connect(_on_approach_enter)
	approach_state.on_exit.connect(_on_approach_exit)
	approach_state.on_physics_update.connect(_on_approach_physics_update)
	var sniper_state = $FSM/Sniper
	sniper_state.on_enter.connect(_on_sniper_enter)
	sniper_state.on_exit.connect(_on_sniper_exit)
	sniper_state.on_physics_update.connect(_on_sniper_physics_update)
	var ring_state = $FSM/Ring
	ring_state.on_enter.connect(_on_ring_enter)
	ring_state.on_exit.connect(_on_ring_exit)
	ring_state.on_physics_update.connect(_on_ring_physics_update)

	_idle_timer = _make_timer(func(): fsm.transition_to("Wander"))
	_wander_timer = _make_timer(func(): fsm.transition_to("Idle"))
	_charge_timer = _make_timer(_fire_sniper_shot)

	# FSM started here to avoid missing the first enter call
	$FSM.start()

func _make_timer(on_timeout: Callable) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.timeout.connect(on_timeout)
	add_child(timer)
	return timer

func _get_player() -> Node2D:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0]

func _probe_sees_player(probe: RayCast2D) -> bool:
	var collider = probe.get_collider()
	return collider != null and collider.is_in_group("player")

# --- Idle -------------------------------------------------------------------

func _detect_player() -> bool:
	var player = _get_player()
	if not player:
		return false
	detect_probe.look_at(player.global_position)
	if _probe_sees_player(detect_probe):
		fsm.transition_to("Approach")
		return true
	return false

func _on_idle_enter() -> void:
	detect_probe.enabled = true
	velocity = Vector2.ZERO
	_idle_timer.start(randf_range(1.5, 4.0))
	sprite.play("idle")

func _on_idle_exit() -> void:
	detect_probe.enabled = false
	_idle_timer.stop()

func _on_idle_physics_update(_delta: float) -> void:
	_detect_player()

func _on_wander_enter() -> void:
	detect_probe.enabled = true
	_wander_dir = Vector2.from_angle(randf() * TAU)
	_wander_timer.start(randf_range(0.4, 1.2))
	sprite.play("run")

func _on_wander_exit() -> void:
	detect_probe.enabled = false
	_wander_timer.stop()

func _on_wander_physics_update(_delta: float) -> void:
	if _detect_player():
		return
	velocity = _wander_dir * wander_speed
	move_and_slide()
	_update_facing(_wander_dir.x)

# --- Approach ---------------------------------------------------------------

func _on_approach_enter() -> void:
	detect_probe.enabled = true
	sniper_probe.enabled = true
	sprite.play("run")

func _on_approach_exit() -> void:
	detect_probe.enabled = false
	sniper_probe.enabled = false

func _on_approach_physics_update(_delta: float) -> void:
	var player = _get_player()
	if not player:
		fsm.transition_to("Idle")
		return

	var to_player = player.global_position - global_position
	_update_facing(to_player.x)
	detect_probe.look_at(player.global_position)
	sniper_probe.look_at(player.global_position)

	if not _probe_sees_player(detect_probe):
		fsm.transition_to("Idle")
		return

	if _probe_sees_player(sniper_probe):
		fsm.transition_to("Sniper")
		return

	velocity = to_player.normalized() * speed
	move_and_slide()

# --- Sniper -----------------------------------------------------------------

func _on_sniper_enter() -> void:
	detect_probe.enabled = true
	sniper_probe.enabled = true
	close_probe.enabled = true
	velocity = Vector2.ZERO
	sprite.play("idle")

func _on_sniper_exit() -> void:
	detect_probe.enabled = false
	sniper_probe.enabled = false
	close_probe.enabled = false
	# Drop any wind-up in progress so we don't fire after leaving the state.
	_charge_timer.stop()

func _on_sniper_physics_update(_delta: float) -> void:
	var player = _get_player()
	if not player:
		fsm.transition_to("Idle")
		return

	var to_player = player.global_position - global_position
	_update_facing(to_player.x)
	detect_probe.look_at(player.global_position)
	sniper_probe.look_at(player.global_position)
	close_probe.look_at(player.global_position)

	if not _probe_sees_player(detect_probe):
		fsm.transition_to("Idle")
		return

	if _probe_sees_player(close_probe):
		fsm.transition_to("Ring")
		return

	# Player backed out of firing range -> close the gap again.
	if not _probe_sees_player(sniper_probe):
		fsm.transition_to("Approach")
		return

	# Start a new wind-up when none is running; it fires via _fire_sniper_shot, then re-arms.
	if _charge_timer.is_stopped():
		sprite.play("attack")
		_charge_timer.start(charge_time)

func _fire_sniper_shot() -> void:
	var player = _get_player()
	if player:
		sniper_node.try_fire(global_position, player.global_position, skill)

# --- Ring -------------------------------------------------------------------

func _on_ring_enter() -> void:
	detect_probe.enabled = true
	close_probe.enabled = true
	sprite.play("attack")

func _on_ring_exit() -> void:
	detect_probe.enabled = false
	close_probe.enabled = false

func _on_ring_physics_update(_delta: float) -> void:
	var player = _get_player()
	if not player:
		fsm.transition_to("Idle")
		return

	var to_player = player.global_position - global_position
	_update_facing(to_player.x)
	detect_probe.look_at(player.global_position)
	close_probe.look_at(player.global_position)

	# Back away while spraying a ring of bullets to open up sniping distance.
	velocity = -to_player.normalized() * retreat_speed
	move_and_slide()
	ring_node.try_fire(global_position, player.global_position, skill)

	if not _probe_sees_player(detect_probe):
		fsm.transition_to("Idle")
	elif not _probe_sees_player(close_probe):
		fsm.transition_to("Sniper")

# --- Shared -----------------------------------------------------------------

# Faces the sprite toward horizontal movement/target. Sprites default to facing
# right, so flip when the target is to the left. Ignores near-vertical headings
# to avoid flicker.
func _update_facing(dir_x: float) -> void:
	if absf(dir_x) > 0.01:
		sprite.flip_h = dir_x < 0.0

func die() -> void:
	queue_free()

func _on_hurt(damage: int) -> void:
	health -= damage
	if health <= 0:
		die()
