extends Node2D

## Blink effect: pick a landing spot and put the caster on it. Faction-agnostic like every
## other spell — it asks the caster for its aim and its target, nothing more.
##
## A hop is refused rather than forced when terrain is in the way: the ray from here to
## there has to be clear, or the caster stays put. Retries jitter the bearing, so a blink
## with a wall on one side finds the open side instead of failing outright.

const ATTEMPTS := 5

var data: BlinkResource
var _caster: Node2D

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	_caster = caster
	global_position = caster.global_position

func _ready() -> void:
	for attempt in ATTEMPTS:
		var to := _destination(attempt)
		if _clear(_caster.global_position, to):
			_caster.global_position = to
			break
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

func _clear(from: Vector2, to: Vector2) -> bool:
	# Terrain only (physics layer 1): blinking through a creature is fine, through a wall
	# is not — the scenes spell the layer out the same way (see their collision masks).
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	return _caster.get_world_2d().direct_space_state.intersect_ray(query).is_empty()
