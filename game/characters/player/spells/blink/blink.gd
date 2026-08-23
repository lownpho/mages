extends Node2D

## Blink effect: pick a landing spot and put the caster on it. Walls are not in the way —
## only the DESTINATION has to be free floor, so the hop crosses anything with another side
## and refuses only a landing inside rock. Retries jitter the bearing, so a blink pointed at
## a solid slab finds the open side instead of failing outright.
##
## Arriving is a flash of light, and light is what sets spores off: a hop into your own field
## lights it at both ends (see SporeCloud).

const ATTEMPTS := 5

var data: BlinkResource
var ctx: CastContext

var _caster: Node2D

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	_caster = caster
	ctx = CastContext.new(spell, caster)
	global_position = caster.global_position

func _ready() -> void:
	for attempt in ATTEMPTS:
		var to := _destination(attempt)
		if _clear(to):
			var from := _caster.global_position
			_caster.global_position = to
			SporeCloud.light(from, ctx.target_groups)
			SporeCloud.light(to, ctx.target_groups)
			# The node stays put at the departure point (setup put it there), so the
			# afterimage plays where the caster was and outlives the hop it resolved.
			$Poof.animation_finished.connect(queue_free)
			$Poof.show()
			$Poof.play()
			return
	queue_free()

func _destination(attempt: int) -> Vector2:
	var distance := data.distance_tiles * GameConstants.PX_PER_TILE
	# Later attempts fan out from the first choice rather than re-rolling it, so the
	# retries are "a bit further round" rather than a second unrelated hop.
	var jitter := deg_to_rad(randf_range(-40.0, 40.0) * attempt)
	if data.landing == BlinkResource.LANDING_RANDOM:
		return _caster.global_position + Vector2.RIGHT.rotated(randf() * TAU) * distance
	var aim: Vector2 = _caster.get_aim_direction().rotated(jitter)
	if data.landing == BlinkResource.LANDING_BEHIND and _caster.has_method("get_target"):
		var target: Node2D = _caster.get_target()
		if target:
			return target.global_position + aim * distance
	return _caster.global_position + aim * distance

func _clear(to: Vector2) -> bool:
	# Terrain only (physics layer 1), and only where it lands: what stands between here and
	# there is exactly what a blink is for. A point rather than the body's own shape — a
	# landing that clips an edge is depenetrated on the next move, and demanding a whole
	# body's clearance would refuse the tight gaps the spell is bought for.
	var query := PhysicsPointQueryParameters2D.new()
	query.position = to
	query.collision_mask = 1
	return _caster.get_world_2d().direct_space_state.intersect_point(query, 1).is_empty()
