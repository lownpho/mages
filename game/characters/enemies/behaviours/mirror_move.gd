extends Behaviour
class_name MirrorMove

# Holds a fixed standoff and mirrors the player's lateral strafe — step left and it
# slides the opposite way, so you can't circle-strafe it; you have to break rhythm or
# walk straight in. Fires inline while it dances, so it needs no separate attack state.

@export var detect_probe_path: NodePath
@export var weapon_path: NodePath
@export var weapon_data: WeaponResource
@export var lost_state: String = "Idle"
@export var standoff: float = 72.0 ## Distance (px) it tries to keep from the target.
@export var speed: float = 42.0
@export var run_anim: String = "run"

@onready var _detect: RayCast2D = get_node(detect_probe_path)
@onready var _weapon: CreatureWeapon = get_node(weapon_path)
var _prev_target: Vector2 = Vector2.ZERO

func _ready() -> void:
	super()
	if weapon_data:
		_weapon.setup_for_creature(weapon_data)

func enter() -> void:
	_detect.enabled = true
	creature.play(run_anim)
	var t := creature.get_target()
	_prev_target = t.global_position if t else creature.global_position

func exit() -> void:
	_detect.enabled = false

func physics_update(_delta: float) -> void:
	var target := creature.get_target()
	if not target:
		creature.fsm.transition_to(lost_state)
		return
	if not creature.look_for_target(_detect):
		creature.fsm.transition_to(lost_state)
		return

	var to_target := target.global_position - creature.global_position
	var dist := to_target.length()
	var fwd := to_target.normalized()
	var perp := Vector2(-fwd.y, fwd.x)

	# The player's lateral movement since last frame, mirrored onto the opposite side.
	var pmove := target.global_position - _prev_target
	_prev_target = target.global_position
	var strafe := -perp * signf(pmove.dot(perp)) * speed

	# Ease back toward the standoff band along the facing axis.
	var closing := fwd * clampf(dist - standoff, -1.0, 1.0) * speed

	creature.velocity = strafe + closing
	creature.move_and_slide()
	creature.face(fwd.x)
	_weapon.try_fire(creature.global_position, target.global_position)
