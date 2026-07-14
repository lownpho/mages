extends Behaviour
class_name RotatingRingBurst

# Offset rings: a full RingPattern fired repeatedly, its aim angle nudged a fixed amount
# each pulse. No single pulse has a gap, but the gaps between successive pulses drift, so
# the overlay reads as a slow rotating spiral to weave through rather than a static wall.

@export var weapon_path: NodePath
@export var weapon_data: WeaponResource
@export var duration: float = 6.0
@export var pulse_interval: float = 0.6
@export var rotation_per_pulse: float = 40.0 ## degrees
@export var done_state: String = "Pattern"
@export var attack_anim: String = "attack"

@onready var _weapon: CreatureWeapon = get_node(weapon_path)
var _duration_timer: Timer
var _pulse_timer: Timer
var _angle: float = 0.0

func _ready() -> void:
	super()
	if weapon_data:
		_weapon.setup_for_creature(weapon_data)
	_duration_timer = creature.make_timer(func(): creature.fsm.transition_to(done_state))
	_pulse_timer = creature.make_timer(_pulse)

func enter() -> void:
	creature.velocity = Vector2.ZERO
	creature.play(attack_anim)
	_angle = randf() * 360.0
	_duration_timer.start(duration)
	_pulse_timer.start(pulse_interval)

func exit() -> void:
	_duration_timer.stop()
	_pulse_timer.stop()

func _pulse() -> void:
	var dir := Vector2.RIGHT.rotated(deg_to_rad(_angle))
	_weapon.try_fire(creature.global_position, creature.global_position + dir)
	_angle += rotation_per_pulse
	_pulse_timer.start(pulse_interval)
