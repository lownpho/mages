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
## Seconds of unbroken no-LOS before the gate gives up. 0 drops the chase the frame sight
## breaks, which is right for a creature that only hunts what it can see; a pursuit that
## follows a commitment (the stalker dropping its disguise — re-hiding because a trunk slid
## between them for a frame reads as a bug) buys itself a moment to keep looking.
@export var lost_grace: float = 0.0
## Seconds before the pursuit gives up. 0 = no clock.
@export var duration: float = 0.0
## Where the clock lands. Falls back to lost_state when empty.
@export var done_state: String = ""

@export_group("Arrival")
## Range for the attack this pursuit is feeding. Unset = this beat never arrives.
@export var attack_probe_path: NodePath
@export var attack_state: String = ""
## Where arriving lands while `attack_state` is still cooling — the recovery Hold, so the
## creature plants at its range and waits the cooldown out. Empty keeps closing, which is
## what a melee pursuit wants; for anything that fights from a distance, leaving it empty
## means every re-approach walks a full cooldown's worth of pixels into the target's face.
@export var wait_state: String = ""

@export_group("Weave")
## Sideways sway relative to forward speed. 0 = a straight line.
@export var weave_amplitude: float = 0.0
@export var weave_frequency: float = 2.0

var _chase: RayCast2D
var _attack: RayCast2D
var _timer: Timer
var _lost_time: float = 0.0
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
	_lost_time = 0.0
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

	# look_for_target, not a bare look_at + probe_sees: a raycast reports the aim it had at
	# the START of the physics step, so reading it directly answers for last frame's aim —
	# and on the entry frame, for a probe that was only just enabled, it answers "nothing
	# there" no matter where the target is. That false negative bounced every LOS-gated
	# chase straight back out to lost_state for one frame; harmless when that's an idle,
	# a reveal/re-hide strobe when it isn't.
	#
	# Arriving is a question about distance, firing a question about the cooldown; answering
	# both with one gate is what walked a ranged creature into the target's face — it reached
	# its range mid-cooldown, the gate said "not yet", and the pursuit simply kept going. So
	# arrival ends the pursuit either way, parking at wait_state when the attack can't fire.
	if _attack and creature.look_for_target(_attack):
		if _attack_ready():
			go_to(attack_state)
			return
		if wait_state != "":
			go_to(wait_state)
			return
	if _chase:
		if creature.look_for_target(_chase):
			_lost_time = 0.0
		else:
			_lost_time += delta
			if _lost_time >= lost_grace:
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

# Arriving asks the same eligibility question a Hold asks before handing off. Without it a
# chase that reaches range while its spell is still cooling drops into a Cast that can't cast:
# the beat plays a full attack animation with no shot in it and bounces straight back out, so
# a long cooldown reads as a creature strobing between running and swinging at nothing.
func _attack_ready() -> bool:
	var state: State = creature.fsm.states.get(attack_state)
	return not (state is Behaviour) or state.can_run()

# Losing the target and running out of clock are both "the pursuit failed"; a beat only
# needs to name the second destination when it differs.
func _lost() -> String:
	return lost_state if lost_state != "" else done_state

func _done() -> String:
	return done_state if done_state != "" else lost_state
