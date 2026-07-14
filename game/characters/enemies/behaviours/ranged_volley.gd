extends Volley
class_name RangedVolley

# A Volley that only presses its attack while the target sits in range: each frame it
# aims its own attack_probe at the target and, the moment they clear it, bails to
# out_of_range_state (a reposition/chase) instead of lobbing shots into the void. Once
# the burst is spent it hands off to done_state like any Volley. The pairing is a poke
# loop — fire from range, and if the player runs, uproot after them and resume.

@export var attack_probe_path: NodePath
@export var out_of_range_state: String = "Chase"

@onready var _probe: RayCast2D = get_node(attack_probe_path)

func enter() -> void:
	_probe.enabled = true
	super()

func exit() -> void:
	_probe.enabled = false

func physics_update(delta: float) -> void:
	var player := creature.get_target()
	if player and not creature.look_for_target(_probe):
		creature.fsm.transition_to(out_of_range_state)
		return
	super(delta)
