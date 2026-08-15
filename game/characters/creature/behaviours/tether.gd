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
## >0 swaps the orbit for a single-file queue trailing the anchor, this many pixels per
## place in line — a retinue marching behind you rather than a swarm circling you.
@export var queue_spacing: float = 0.0
@export var fly_anim: String = "fly"

@onready var _detect: RayCast2D = get_node(detect_probe_path)
var _phase: float = -1.0
# Last heading the anchor actually moved in; a standing anchor keeps the line where it is.
var _behind: Vector2 = Vector2.LEFT

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
	var to_slot: Vector2
	if queue_spacing > 0.0:
		var vel = anchor.get("velocity")
		if vel and vel.length() > 1.0:
			_behind = -vel.normalized()
		to_slot = anchor.global_position + _behind * queue_spacing * (_rank() + 1) - creature.global_position
		# One speed: a marching line doesn't ease in. Capped by the distance left, so it
		# lands on the slot instead of jittering across it.
		creature.velocity = to_slot.normalized() * minf(follow_speed, to_slot.length() / delta)
	else:
		_phase += orbit_speed * delta
		to_slot = anchor.global_position + Vector2(orbit_radius, 0).rotated(_phase) - creature.global_position
		# Proportional chase capped at follow_speed: snappy when far, gentle on the slot.
		creature.velocity = (to_slot * 6.0).limit_length(follow_speed)
	creature.move_and_slide()
	creature.face(to_slot.x)

# Place in line: how many summons of the same kind sit ahead of us in tree order (i.e. were
# summoned first). Recomputed each frame so the queue closes up when one dies or peels off
# to fight; only same-scene siblings count, so a bzzz swarm doesn't punch holes in the line.
func _rank() -> int:
	var rank := 0
	for other in get_tree().get_nodes_in_group("summon"):
		if other == creature:
			break
		if other.scene_file_path == creature.scene_file_path:
			rank += 1
	return rank

func _anchor() -> Node2D:
	var nodes := get_tree().get_nodes_in_group(anchor_group)
	return nodes[0] if not nodes.is_empty() else null
