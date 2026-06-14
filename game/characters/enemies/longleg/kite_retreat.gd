extends Behaviour
class_name KiteRetreat

@export var detect_probe_path: NodePath
@export var close_probe_path: NodePath
@export var weapon_path: NodePath
@export var weapon_data: WeaponResource
@export var retreat_speed: float = 34.0
@export var lost_state: String = "Idle"
@export var regain_state: String = "Snipe"

@onready var _detect: RayCast2D = get_node(detect_probe_path)
@onready var _close: RayCast2D = get_node(close_probe_path)
@onready var _weapon: CreatureWeapon = get_node(weapon_path)

func _ready() -> void:
	super()
	if weapon_data:
		_weapon.setup_for_creature(weapon_data)

func enter() -> void:
	_detect.enabled = true
	_close.enabled = true
	creature.play("attack")

func exit() -> void:
	_detect.enabled = false
	_close.enabled = false

func physics_update(_delta: float) -> void:
	var player := creature.get_target()
	if not player:
		creature.fsm.transition_to(lost_state)
		return

	var to_player := player.global_position - creature.global_position
	creature.face(to_player.x)
	_detect.look_at(player.global_position)
	_close.look_at(player.global_position)

	creature.velocity = -to_player.normalized() * retreat_speed
	creature.move_and_slide()
	_weapon.try_fire(creature.global_position, player.global_position)

	if not creature.probe_sees(_detect):
		creature.fsm.transition_to(lost_state)
	elif not creature.probe_sees(_close):
		creature.fsm.transition_to(regain_state)
