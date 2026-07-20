extends Volley
class_name RotatingVolley

# A Volley whose aim angle drifts a fixed amount per shot, so a RingPattern's gaps move
# pulse to pulse instead of firing through the same lanes every time — the overlay reads
# as a slow rotating spiral to weave through rather than a static wall.
#
# `aim_at_target` picks which kind of spiral: on (default) the drift rides on top of the
# player's bearing, so the burst still tracks them (rosebud, thornmess's bloom); off, the
# aim is absolute from a random starting angle and the target is ignored entirely — the
# arena-painting spore screen. Pair the latter with duration + pulse_interval.

@export var rotation_per_pulse: float = 30.0 ## degrees
@export var aim_at_target: bool = true

var _bonus_angle: float = 0.0

func enter() -> void:
	_bonus_angle = 0.0 if aim_at_target else randf() * 360.0
	super()

func _fire(player: Node2D) -> bool:
	var base := aim_at(player) if aim_at_target else Vector2.RIGHT
	var fired := _caster.cast(spell, base.rotated(deg_to_rad(_bonus_angle)))
	if fired:
		_bonus_angle += rotation_per_pulse
	return fired

func _requires_target() -> bool:
	return aim_at_target
