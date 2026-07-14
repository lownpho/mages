extends Volley
class_name RotatingVolley

# Same as Volley, but each successful shot nudges the aim angle by a fixed amount so a
# RingPattern's gaps drift pulse to pulse instead of firing through the same lanes every
# time — reads as a slow rotating spiral (see FaeRings, its duration-based cousin).

@export var rotation_per_pulse: float = 30.0 ## degrees

var _bonus_angle: float = 0.0

func enter() -> void:
	_bonus_angle = 0.0
	super()

func _fire(player: Node2D) -> bool:
	var aim := (player.global_position - creature.global_position).rotated(deg_to_rad(_bonus_angle))
	var fired := _weapon.try_cast(creature.global_position, creature.global_position + aim)
	if fired:
		_bonus_angle += rotation_per_pulse
	return fired
