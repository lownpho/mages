extends Behaviour
class_name FireWhenInRange

## Hysteresis margin (px) the exit probe reaches past the attack probe. Attack is entered
## on the short attack probe (Chase's call) but only left once the player clears this
## longer exit probe, so a player slower than the enemy can't sit on the attack boundary
## and strobe Chase <-> Attack. Derived per-enemy from its own attack probe, so the whole
## roster gets the deadband without a second probe node in every scene.
const EXIT_MARGIN := 8.0

@export var weapon_path: NodePath
@export var weapon_data: WeaponResource
@export var attack_probe_path: NodePath
@export var out_of_range_state: String = "Chase"
@export var attack_anim: String = "idle" ## Played while firing; defaults to the idle pose.

@onready var _weapon: CreatureWeapon = get_node(weapon_path)
@onready var _probe: RayCast2D = get_node(attack_probe_path)
var _exit_probe: RayCast2D

func _ready() -> void:
	super()
	if weapon_data:
		_weapon.setup_for_creature(weapon_data)
	# Child of the attack probe so it inherits the per-frame look_at aim for free; only its
	# length differs.
	_exit_probe = RayCast2D.new()
	_exit_probe.collision_mask = _probe.collision_mask
	_exit_probe.target_position = Vector2(_probe.target_position.length() + EXIT_MARGIN, 0)
	_exit_probe.hit_from_inside = true
	_exit_probe.enabled = false
	_probe.add_child(_exit_probe)

func enter() -> void:
	_probe.enabled = true
	_exit_probe.enabled = true
	creature.play(attack_anim)

func exit() -> void:
	_probe.enabled = false
	_exit_probe.enabled = false

func physics_update(_delta: float) -> void:
	var player := creature.get_target()
	if not player:
		creature.fsm.transition_to(out_of_range_state)
		return

	_probe.look_at(player.global_position)
	creature.face(player.global_position.x - creature.global_position.x)

	# Leave only when the player clears the longer exit probe; keep firing (gated on the
	# attack probe) while inside it. The gap between the two is the hysteresis deadband.
	if creature.probe_sees(_exit_probe):
		if creature.probe_sees(_probe):
			_weapon.try_fire(creature.global_position, player.global_position)
	else:
		creature.fsm.transition_to(out_of_range_state)
