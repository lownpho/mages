extends TimedChase
class_name ChaseIntoRange

# Same timed pursuit as TimedChase, but breaks early once its own attack_probe sees the
# target — the same raycast-and-probe convention every other enemy's Chase/FireWhenInRange
# uses (probe length is the range, LOS-checked via probe_sees, not a plain distance check)
# — so a pattern dispatcher can send the boss after its own attack's effective range (melee
# vs. ranged). The timeout still guarantees a hand-off even against a target that stays out
# of reach or ducks behind a wall.

@export var attack_probe_path: NodePath
## Where a *successful* close hands off, when that differs from done_state: getting there
## is the cue for the attack the range was for, while a timeout or a target that slipped
## away must still fall back to the dispatcher — otherwise a boss that can't catch a
## kiting player ping-pongs between the chase and an attack it's never in range to use.
@export var reached_state: String = ""

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

func _reached_state() -> String:
	return reached_state if reached_state != "" else done_state
