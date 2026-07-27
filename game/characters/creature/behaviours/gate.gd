extends Behaviour
class_name Gate

# The sequenced boss's dispatcher: an ORDERED ladder where PatternPicker is a weighted roll.
# It hands off to the first listed beat willing to run, so precedence is authored as position
# in the list and what happens next is decided by what is TRUE — a brood still standing, a
# spell still cooling, a health window — rather than by dice. A fight built out of these reads
# as a rotation the player can learn and steer, which a roll can never be.
#
# The beats gate themselves through the same can_run() the roll dispatcher asks, so a phase
# swap is two mutually-exclusive health windows sitting at adjacent rungs, and the ladder's
# last rung is its floor: something always eligible (a Hold) so the dispatcher can't deadlock.

## Beat names in precedence order. The first whose can_run() passes takes the hand-off.
@export var beats: Array[String] = []

@export_group("Detection")
## Optional LOS probe; leave empty to always dispatch.
@export var probe_path: NodePath
@export var lost_state: String = "Idle"

func enter() -> void:
	creature.velocity = Vector2.ZERO
	# Deferred for the same reason PatternPicker defers: let the FSM finish entering this
	# state before transition_to takes us straight back out of it.
	call_deferred("_dispatch")

# A dispatcher is ready exactly when it has something to dispatch, so a Hold pointed here
# waits out the ladder's cooldowns instead of bouncing through every frame.
func _ready_to_run() -> bool:
	return beats.is_empty() or _first_ready() != ""

func _dispatch() -> void:
	if probe_path != NodePath():
		var probe: RayCast2D = get_node(probe_path)
		if not creature.look_for_target(probe):
			go_to(lost_state)
			return
	var beat := _first_ready()
	if beat == "" and not beats.is_empty():
		beat = beats[beats.size() - 1]
	if beat != "":
		go_to(beat)

func _first_ready() -> String:
	for beat in beats:
		var state: State = creature.fsm.states.get(beat)
		if state == null:
			continue
		if not (state is Behaviour) or state.can_run():
			return beat
	return ""
