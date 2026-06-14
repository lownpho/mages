extends Behaviour
class_name SniperCharge

# Holds position and snipes: a wind-up charge before each shot, repeating while the
# target sits in the sniper band. Three nested probes hand off — too close, too far
# (drifted out of the band but still seen), or lost entirely.

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
@onready var _weapon: CreatureWeapon = get_node(weapon_path)
var _charge: Timer

func _ready() -> void:
	super()
	if weapon_data:
		_weapon.setup_for_creature(weapon_data)
	_charge = creature.make_timer(_fire_shot)

func enter() -> void:
	_detect.enabled = true
	_sniper.enabled = true
	_close.enabled = true
	creature.velocity = Vector2.ZERO
	creature.play("idle")

func exit() -> void:
	_detect.enabled = false
	_sniper.enabled = false
	_close.enabled = false
	_charge.stop()  # defensive: clear any pending wind-up on the way out

func physics_update(_delta: float) -> void:
	var player := creature.get_target()
	if player:
		creature.face(player.global_position.x - creature.global_position.x)
		_detect.look_at(player.global_position)
		_sniper.look_at(player.global_position)
		_close.look_at(player.global_position)

	# Once a wind-up is running we're committed: keep tracking the player and let
	# the shot fire before any range check can pull us out of the state.
	if not _charge.is_stopped():
		return

	if not player or not creature.probe_sees(_detect):
		creature.fsm.transition_to(lost_state)
		return
	if creature.probe_sees(_close):
		creature.fsm.transition_to(too_close_state)
		return
	if not creature.probe_sees(_sniper):
		creature.fsm.transition_to(too_far_state)
		return

	# In the band and free to act: arm the next wind-up; it fires via _fire_shot.
	creature.play("attack")
	_charge.start(charge_time)

func _fire_shot() -> void:
	var player := creature.get_target()
	if player:
		_weapon.try_fire(creature.global_position, player.global_position)
