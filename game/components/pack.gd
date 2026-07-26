extends Node
class_name Pack

## Pack aggro. The moment one member engages — it spotted the target, or took a hit and its
## calm beat woke it — every packmate within its radius engages too, and each of those calls
## its own packmates from its own position, so an alert walks a strung-out pack instead of
## stopping dead at one radius.
##
## The trigger is the calm→engaged edge on the FSM rather than any one cause, so detection and
## being shot rally the pack through a single hook, and only genuine news travels: a member
## re-closing between bursts was never calm, so it doesn't shout again.
##
## Membership IS this node's group, so no node means no pack, a mixed pack is free (an alpha
## just joins its underlings' group), and a call lands on the component that answers without
## anything having to look it up. It sits beside the FSM like Hurtbox rather than inside it,
## because waking is an edge into a state, not a state of its own.

## Group to call. Author the same name on this node's Groups list too — one is who we shout
## to, the other is who hears us, and setting only one silently half-wires the pack.
@export var group: StringName = &""
## How far a call carries. Checked on the receiving end, so members may differ.
@export var radius_tiles: float = 8.0
## The state that counts as engaged: entering it shouts, and answering a call lands here. It
## closes on the target from there by itself — Creature.get_target() has no distance cap, so
## the caller's position never has to travel with the call.
@export var alert_state: String = "Chase"
## The calm states: the ones a call can interrupt, and the ones we must be leaving for
## entering `alert_state` to count as news. Doubles as the relay's terminator — a member
## already in the fight neither answers nor re-broadcasts, so a cycle dies on its second hop.
@export var from_states: Array[String] = ["Idle", "Wander"]

var _creature: Creature

func _ready() -> void:
	_creature = get_parent() as Creature
	# Children are ready before their parent, so Creature's @onready fsm isn't assigned yet —
	# defer the hookup (the same ordering fsm.start() works around).
	_hook_fsm.call_deferred()

func _hook_fsm() -> void:
	_creature.fsm.state_changed.connect(_on_state_changed)

## A packmate at `origin` just engaged and wants company.
func pack_alert(origin: Vector2) -> void:
	var radius := radius_tiles * GameConstants.PX_PER_TILE
	if origin.distance_squared_to(_creature.global_position) > radius * radius:
		return
	if not _is_calm(_creature.fsm.current_state):
		return
	# Engaging is itself the shout (below), so this one line both wakes us and relays.
	_creature.fsm.transition_to(alert_state)

func _on_state_changed(previous: State, current: State) -> void:
	if group == &"" or String(current.name) != alert_state or not _is_calm(previous):
		return
	for node in get_tree().get_nodes_in_group(group):
		var mate := node as Pack
		if mate and mate != self:
			mate.pack_alert(_creature.global_position)

func _is_calm(state: State) -> bool:
	return state != null and String(state.name) in from_states
