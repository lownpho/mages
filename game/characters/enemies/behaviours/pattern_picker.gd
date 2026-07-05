extends Behaviour
class_name PatternPicker

# The boss dispatcher: rolls a weighted pick among `states` and hands off immediately —
# deferred one frame (not called straight from enter()) so the FSM finishes entering this
# state before transition_to re-enters it. An optional detect probe lets a boss bail to
# lost_state instead of rolling when the player has actually slipped away, rather than
# committing to a pattern against no one. Reusable by any future boss that cycles attacks.

@export var states: Array[String] = []
@export var weights: Array[float] = []
@export var detect_probe_path: NodePath ## optional; leave empty to always roll
@export var lost_state: String = "Idle"

func enter() -> void:
	creature.velocity = Vector2.ZERO
	call_deferred("_dispatch")

func _dispatch() -> void:
	if detect_probe_path != NodePath():
		var probe: RayCast2D = get_node(detect_probe_path)
		if not creature.look_for_target(probe):
			creature.fsm.transition_to(lost_state)
			return

	if states.is_empty():
		return

	var total := 0.0
	for w in weights:
		total += w
	var roll := randf() * total
	var acc := 0.0
	for i in range(states.size()):
		acc += weights[i]
		if roll <= acc:
			creature.fsm.transition_to(states[i])
			return
	creature.fsm.transition_to(states[states.size() - 1])
