extends TimedChase
class_name ChaseIntoRange

# Same timed pursuit as TimedChase, but breaks early once its own attack_probe sees the
# target — the same raycast-and-probe convention every other enemy's Chase/FireWhenInRange
# uses (probe length is the range, LOS-checked via probe_sees, not a plain distance check)
# — so a pattern dispatcher can send the boss after its own attack's effective range (melee
# vs. ranged). The timeout still guarantees a hand-off even against a target that stays out
# of reach or ducks behind a wall.

@export var attack_probe_path: NodePath

@onready var _probe: RayCast2D = get_node(attack_probe_path)

func enter() -> void:
	_probe.enabled = true
	super()

func exit() -> void:
	_probe.enabled = false
	super()

func _reached(target: Node2D) -> bool:
	_probe.look_at(target.global_position)
	return creature.probe_sees(_probe)
