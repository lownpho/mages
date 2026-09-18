extends Behaviour
class_name Cycle

## The Boss dispatcher: an ORDERED Rotation where PatternPicker is a weighted roll and Gate is
## an ordered ladder. It walks the BossController's authored Phase list, plays each Phase for
## its authored Reps (identical, so the beat can be read), opens the Phase's punish Tail, then
## advances — wrapping, and carrying Intensity across the wrap.
##
## The beats keep doing their own work: each Phase beat hands back here when its own burst
## ends (`done_state = "Cycle"`), and Cycle decides whether that was a Rep, the last Rep, or a
## Phase that never got to run. The pauses (rep gap, Tail, Free beat) belong to this state,
## which is why the punish window is open here and nowhere else.
##
## Everything it waits on is asked of the beat itself: a Phase that is still cooling, or whose
## escort still stands, is waited out; a Phase whose window has shut for good (`once` spent, a
## health window the fight has left) is skipped rather than waited on forever.

## Where the beat's own `can_run` questions are asked from. Empty = fire from anywhere.
@export var probe_path: NodePath
@export var lost_state: String = "Idle"
## Non-counterable pause between Phases. Capped at BossController.FREE_BEAT_CAP — pacing, never
## a free damage window.
@export_range(0.0, BossController.FREE_BEAT_CAP) var free_beat: float = 1.2
## Pose held during a Phase's Tail (the punish window).
@export var tail_anim: String = "idle"

## What Cycle is doing between beats. WAIT kinds resolve when the world changes (a cooldown
## lapses, an escort dies) rather than on their own clock.
enum Pause { NONE, REP_GAP, TAIL, FREE, REP_WAIT, ADDS_WAIT }

var _boss: BossController
## The Phase being fought, and whether Cycle is currently waiting on a beat it handed off to.
var _beat: Behaviour
var _pause: Pause = Pause.NONE
var _left: float = 0.0
var _dispatched: bool = false

func _ready() -> void:
	super()
	_boss = boss()

func enter() -> void:
	creature.velocity = Vector2.ZERO
	# Deferred for the same reason PatternPicker and Gate defer: let the FSM finish entering
	# this state before transition_to takes us straight back out of it.
	call_deferred("_dispatch")

# A dispatcher is ready exactly when it has something to dispatch — beats names a Rotation, so
# a Hold pointed here waits out the Phase it can't play rather than bouncing every frame.
func _ready_to_run() -> bool:
	return _boss == null or not _boss.phases.is_empty()

func physics_update(delta: float) -> void:
	match _pause:
		Pause.NONE:
			pass
		Pause.REP_WAIT:
			if _beat and _beat.can_run():
				_pause = Pause.NONE
				_play()
		Pause.ADDS_WAIT:
			# The adds ARE the Phase's answer: it is not over until they are down.
			if _beat and _beat.group_clear():
				_pause = Pause.NONE
				_close_phase()
		_:
			_left -= delta
			if _left <= 0.0:
				_resolve_pause()

func _dispatch() -> void:
	# The hand-off was queued a frame ago; if the scene was torn down in between (the player
	# died and the run bounced to the title) there is nothing left to dispatch into.
	if not is_inside_tree() or _boss == null:
		return
	if probe_path != NodePath():
		var probe: RayCast2D = get_node(probe_path)
		if not creature.look_for_target(probe):
			_dispatched = false
			go_to(lost_state)
			return
	# A beat we handed off to has come back: that is one Rep of the current Phase, played. The
	# name check is what keeps a stale hand-off (a leash reset re-entering the fight) from
	# counting a Rep against the Phase the fight has moved on to.
	if _dispatched and _beat != null and _beat.name == _boss.cursor_phase_name():
		_dispatched = false
		_beat_done()
		return
	if _beat == null or _beat.name != _boss.cursor_phase_name():
		_load_phase()
	_play()

# --- the Rotation ----------------------------------------------------------------------

# Take up the Phase the cursor points at (the first one, or wherever the fight had got to).
func _load_phase() -> void:
	_pause = Pause.NONE
	_beat = _phase_beat(_boss.cursor_phase_name())
	if _beat:
		_boss.begin_phase(_beat)

# One Rep of the current Phase is done: another one, or the end of the Phase.
func _beat_done() -> void:
	_boss.reps += 1
	if _boss.reps < maxi(_beat.reps, 1):
		_start_pause(Pause.REP_GAP, _boss.scale_gap(_beat.rep_gap))
		return
	_close_phase()

# Everything the Phase is going to do has been done: open its Tail. An ADDS Phase holds here
# until its escort is down, which is what makes clearing the adds the answer.
func _close_phase() -> void:
	if _beat == null:
		return
	if _beat.counter_kind == Behaviour.Counter.ADDS and not _beat.group_clear():
		_pause = Pause.ADDS_WAIT
		return
	_boss.finish_phase()
	_boss.open_tail()
	creature.play(tail_anim, creature.intensity())
	_start_pause(Pause.TAIL, _boss.scale_tail(_beat.tail))

# Hand the current Phase's next Rep off to its beat — or wait, when the beat cannot run yet.
func _play() -> void:
	if _beat == null:
		return
	if not _beat.can_run():
		# A window that has shut for good is a Phase that is over, not one to wait out; a
		# cooling spell or a standing escort is worth the wait.
		if not _beat.window_open():
			_close_phase()
			return
		_pause = Pause.REP_WAIT
		return
	_dispatched = true
	go_to(_beat.name)

# Move the Rotation on: a Phase whose window just opened jumps the queue, otherwise the next
# Phase in the authored order (wrapping to the first).
func _advance() -> void:
	var pick := _priority_phase()
	if pick == null:
		pick = _next_phase()
	if pick == null:
		return
	_beat = pick
	_boss.jump_to(pick.name)
	_start_pause(Pause.FREE, minf(free_beat, BossController.FREE_BEAT_CAP))

# The next Phase in the Rotation that is willing to run, skipping any whose window has shut
# (a spent `once` desperation beat, a health window the fight has left). Falls back to the next
# slot when a whole lap is gated, which is where waiting belongs.
func _next_phase() -> Behaviour:
	var count: int = _boss.phases.size()
	if count == 0:
		return null
	var start := _boss.cursor
	var waiting: Behaviour = null
	for i in count:
		var beat := _phase_beat(_boss.phases[(start + i + 1) % count])
		if beat == null:
			continue
		if beat.can_run():
			return beat
		if waiting == null and beat.window_open():
			waiting = beat
	return waiting if waiting else _phase_beat(_boss.phases[(start + 1) % count])

# A positive-priority Phase jumps the queue: a desperation opener fires the instant its window
# opens rather than waiting for its turn in the Rotation. `once` is what retires it.
func _priority_phase() -> Behaviour:
	var pick: Behaviour = null
	var top := 0
	for name in _boss.phases:
		var beat := _phase_beat(name)
		if beat == null or beat == _beat or beat.priority <= top:
			continue
		if beat.can_run():
			top = beat.priority
			pick = beat
	return pick

func _resolve_pause() -> void:
	match _pause:
		Pause.REP_GAP:
			_pause = Pause.NONE
			_play()
		Pause.FREE:
			_pause = Pause.NONE
			_boss.begin_phase(_beat)
			_play()
		Pause.TAIL:
			_pause = Pause.NONE
			_boss.close_tail()
			_boss.end_phase()
			_advance()
		_:
			_pause = Pause.NONE

func _start_pause(kind: Pause, seconds: float) -> void:
	_pause = kind
	_left = maxf(seconds, 0.0)

func _phase_beat(name: String) -> Behaviour:
	return creature.fsm.states.get(name) as Behaviour