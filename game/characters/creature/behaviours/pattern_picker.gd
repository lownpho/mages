extends Behaviour
class_name PatternPicker

# The boss dispatcher: rolls among the beats sitting beside it in the FSM and hands off
# immediately — deferred one frame (not called straight from enter()) so the FSM finishes
# entering this state before transition_to re-enters it.
#
# The pool is not a list here. Each beat carries its own pattern_weight, health window,
# priority and once-ness (see Behaviour), so adding a move is dropping the node in and
# setting a number on it, with no parallel arrays to keep aligned and no state names to
# mistype. Phases fall out of the health windows: authoring one beat at 0.25..1 and another
# at 0..0.25 swaps the first out for the second at a quarter health.

@export var probe_path: NodePath ## optional; leave empty to always roll
@export var lost_state: String = "Idle"

func enter() -> void:
	creature.velocity = Vector2.ZERO
	call_deferred("_dispatch")

func _dispatch() -> void:
	if probe_path != NodePath():
		var probe: RayCast2D = get_node(probe_path)
		if not creature.look_for_target(probe):
			go_to(lost_state)
			return

	# Beats willing to run right now — a Cast whose spell is still cooling would just stand
	# there, and one outside its health window belongs to another phase of the fight. Fall
	# back to the whole pool when nothing is ready, so the dispatcher always hands off
	# rather than deadlocking on a fully-cooling kit.
	var pool: Array[Behaviour] = []
	var all: Array[Behaviour] = []
	for sibling in get_parent().get_children():
		if sibling == self or not (sibling is Behaviour) or sibling.pattern_weight <= 0.0:
			continue
		all.append(sibling)
		if sibling.can_run():
			pool.append(sibling)
	if pool.is_empty():
		pool = all
	if pool.is_empty():
		return

	# A desperation opener jumps the queue rather than waiting to be rolled.
	var top := 0
	for beat in pool:
		top = maxi(top, beat.priority)
	if top > 0:
		pool = pool.filter(func(beat: Behaviour) -> bool: return beat.priority == top)
	_roll(pool)

func _roll(pool: Array[Behaviour]) -> void:
	var total := 0.0
	for beat in pool:
		total += beat.pattern_weight
	var roll := randf() * total
	var acc := 0.0
	for beat in pool:
		acc += beat.pattern_weight
		if roll <= acc:
			go_to(beat.name)
			return
	go_to(pool[pool.size() - 1].name)
