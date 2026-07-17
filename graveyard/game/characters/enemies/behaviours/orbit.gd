extends Behaviour
class_name Orbit

# Circles the target at a fixed radius for a beat. With a weapon it's the deterrent phase
# (holds the ring and fires); with no `weapon_data` and a wider `radius` it's the recharge
# phase — the drone backs off to a wider orbit and is chaseable. Chain two Orbit nodes
# (fire → recharge → fire) for the drone's dodge-then-punish cycle.

@export var detect_probe_path: NodePath
@export var weapon_path: NodePath
@export var weapon_data: SpellResource ## leave null for a non-firing recharge orbit
@export var lost_state: String = "Idle"
@export var done_state: String = "Recharge"
@export var radius: float = 64.0
@export var speed: float = 60.0
@export var orbit_dir: float = 1.0 ## +1 / -1 = clockwise / counter
@export var duration: float = 2.5
@export var move_anim: String = "fly"

@onready var _detect: RayCast2D = get_node(detect_probe_path)
@onready var _weapon: CreatureSpellCaster = get_node(weapon_path)
var _timer: Timer

func _ready() -> void:
	super()
	if weapon_data:
		_weapon.setup_for_creature(weapon_data)
	_timer = creature.make_timer(func(): creature.fsm.transition_to(done_state))

func enter() -> void:
	_detect.enabled = true
	creature.play(move_anim)
	_timer.start(duration)

func exit() -> void:
	_detect.enabled = false
	_timer.stop()

func physics_update(_delta: float) -> void:
	var target := creature.get_target()
	if not target or not creature.look_for_target(_detect):
		creature.fsm.transition_to(lost_state)
		return
	var to_target := target.global_position - creature.global_position
	var dist := to_target.length()
	# Radial term eases toward the ring; tangential term walks around it.
	var radial := to_target.normalized() * clampf(dist - radius, -1.0, 1.0)
	var tangent := Vector2(-to_target.y, to_target.x).normalized() * orbit_dir
	creature.velocity = (radial + tangent) * speed
	creature.move_and_slide()
	creature.face(to_target.x)
	if weapon_data:
		_weapon.try_cast(creature.global_position, target.global_position)
