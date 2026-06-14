extends Behaviour
class_name Tether

# Hover in a slow orbit around an anchor (e.g. the caster a summoned swarm circles),
# darting off to `alert_state` the moment a target comes within the detect probe. Each
# unit takes a random orbit phase on enter, so a swarm spreads into a ring instead of
# stacking on one point (a stack shares a hurtbox and dies to a single bullet). Faction-
# agnostic: the target is `creature.get_target()`, the anchor is the nearest `anchor_group`
# member. Pair it with a Chase whose `lost_state` points back here so the swarm regroups.

@export var detect_probe_path: NodePath
@export var anchor_group: String = "player"
@export var alert_state: String = "Chase"
@export var follow_speed: float = 55.0
@export var orbit_radius: float = 18.0 ## Distance each unit holds from the anchor.
@export var orbit_speed: float = 2.0   ## Radians/sec the ring rotates, for a live swarm.
@export var fly_anim: String = "fly"

@onready var _detect: RayCast2D = get_node(detect_probe_path)
var _phase: float = -1.0

func enter() -> void:
	_detect.enabled = true
	creature.play(fly_anim)
	if _phase < 0.0:
		_phase = randf() * TAU

func exit() -> void:
	_detect.enabled = false

func physics_update(delta: float) -> void:
	if creature.look_for_target(_detect):
		creature.fsm.transition_to(alert_state)
		return
	var anchor := _anchor()
	if not anchor:
		creature.velocity = Vector2.ZERO
		return
	_phase += orbit_speed * delta
	var slot := anchor.global_position + Vector2(orbit_radius, 0).rotated(_phase)
	var to_slot := slot - creature.global_position
	# Proportional chase capped at follow_speed: snappy when far, gentle on the slot.
	creature.velocity = (to_slot * 6.0).limit_length(follow_speed)
	creature.move_and_slide()
	creature.face(to_slot.x)

func _anchor() -> Node2D:
	var nodes := get_tree().get_nodes_in_group(anchor_group)
	return nodes[0] if not nodes.is_empty() else null
