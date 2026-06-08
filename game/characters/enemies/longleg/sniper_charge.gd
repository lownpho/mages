extends Behaviour
class_name SniperCharge

@export var detect_probe_path: NodePath
@export var sniper_probe_path: NodePath
@export var close_probe_path: NodePath
@export var weapon_path: NodePath
@export var weapon_data: WeaponResource
@export var charge_time: float = 0.9 ## Wind-up before each shot.
@export var lost_state: String = "Idle"
@export var too_close_state: String = "Ring"
@export var too_far_state: String = "Approach"

@onready var _detect: RayCast2D = get_node(detect_probe_path)
@onready var _sniper: RayCast2D = get_node(sniper_probe_path)
@onready var _close: RayCast2D = get_node(close_probe_path)
@onready var _weapon: EnemyWeapon = get_node(weapon_path)
var _charge: Timer

func _ready() -> void:
	super()
	if weapon_data:
		_weapon.setup_for_enemy(weapon_data)
	_charge = enemy.make_timer(_fire_shot)

func enter() -> void:
	_detect.enabled = true
	_sniper.enabled = true
	_close.enabled = true
	enemy.velocity = Vector2.ZERO
	enemy.play("idle")

func exit() -> void:
	_detect.enabled = false
	_sniper.enabled = false
	_close.enabled = false
	_charge.stop()  # cancel an in-progress wind-up so we don't fire after leaving

func physics_update(_delta: float) -> void:
	var player := enemy.get_player()
	if not player:
		enemy.fsm.transition_to(lost_state)
		return

	var to_player := player.global_position - enemy.global_position
	enemy.face(to_player.x)
	_detect.look_at(player.global_position)
	_sniper.look_at(player.global_position)
	_close.look_at(player.global_position)

	if not enemy.probe_sees(_detect):
		enemy.fsm.transition_to(lost_state)
		return
	if enemy.probe_sees(_close):
		enemy.fsm.transition_to(too_close_state)
		return
	if not enemy.probe_sees(_sniper):
		enemy.fsm.transition_to(too_far_state)
		return

	# Arm a wind-up only when none is running; it fires via _fire_shot then re-arms.
	if _charge.is_stopped():
		enemy.play("attack")
		_charge.start(charge_time)

func _fire_shot() -> void:
	var player := enemy.get_player()
	if player:
		_weapon.try_fire(enemy.global_position, player.global_position, enemy.skill)
