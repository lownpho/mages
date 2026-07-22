extends Behaviour
class_name Approach

# Closing the distance, in every shape the roster needs: a plain LOS-gated chase that hands
# off once its attack probe sees the target, a weaving one that's hard to lead, and a boss's
# committed pursuit that ignores line of sight and gives up on a clock instead. Which it is
# comes from which dials are set — an unset probe is simply a gate that never fires.

@export var speed: float = 16.0
@export var anim: String = "run"

@export_group("Pursuit")
## LOS gate. Set, losing sight ends the pursuit; unset, the creature is committed and only
## the clock (or arriving) stops it — a boss shouldn't abort a charge behind a pillar.
@export var chase_probe_path: NodePath
## Where losing the target lands. Falls back to done_state when empty.
@export var lost_state: String = ""
## Seconds before the pursuit gives up. 0 = no clock.
@export var duration: float = 0.0
## Where the clock lands. Falls back to lost_state when empty.
@export var done_state: String = ""

@export_group("Arrival")
## Range for the attack this pursuit is feeding. Unset = this beat never arrives.
@export var attack_probe_path: NodePath
@export var attack_state: String = ""

@export_group("Weave")
## Sideways sway relative to forward speed. 0 = a straight line.
@export var weave_amplitude: float = 0.0
@export var weave_frequency: float = 2.0

var _chase: RayCast2D
var _attack: RayCast2D
var _timer: Timer
var _weave_time: float = 0.0
var _weave_phase: float = 0.0
var _weave_retarget: float = 0.0

func _ready() -> void:
	super()
	if chase_probe_path != NodePath():
		_chase = get_node(chase_probe_path)
	if attack_probe_path != NodePath():
		_attack = get_node(attack_probe_path)
	if duration > 0.0:
		_timer = creature.make_timer(func() -> void: go_to(_done()))

func enter() -> void:
	_weave_time = 0.0
	_weave_retarget = 0.0
	if _chase:
		_chase.enabled = true
	if _attack:
		_attack.enabled = true
	creature.play(anim)
	if _timer:
		_timer.start(duration)

func exit() -> void:
	if _chase:
		_chase.enabled = false
	if _attack:
		_attack.enabled = false
	if _timer:
		_timer.stop()
	creature.velocity = Vector2.ZERO

func physics_update(delta: float) -> void:
	var player := target_or_go(_lost())
	if not player:
		return

	var to_player := player.global_position - creature.global_position
	creature.face(to_player.x)

	if _attack:
		_attack.look_at(player.global_position)
		if creature.probe_sees(_attack):
			go_to(attack_state)
			return
	if _chase:
		_chase.look_at(player.global_position)
		if not creature.probe_sees(_chase):
			go_to(_lost())
			return

	creature.velocity = _heading(to_player, delta) * speed
	creature.move_and_slide()

func _heading(to_player: Vector2, delta: float) -> Vector2:
	var forward := to_player.normalized()
	if weave_amplitude <= 0.0:
		return forward
	_weave_time += delta
	_weave_retarget -= delta
	# Re-roll the phase at random intervals so the weave reads as quick and
	# unpredictable rather than a clean, readable sine.
	if _weave_retarget <= 0.0:
		_weave_retarget = randf_range(0.3, 0.9)
		_weave_phase = randf_range(-PI, PI)
	var sway := sin(_weave_time * weave_frequency + _weave_phase) * weave_amplitude
	return forward + Vector2(-forward.y, forward.x) * sway

# Losing the target and running out of clock are both "the pursuit failed"; a beat only
# needs to name the second destination when it differs.
func _lost() -> String:
	return lost_state if lost_state != "" else done_state

func _done() -> String:
	return done_state if done_state != "" else lost_state
