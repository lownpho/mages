extends Node2D
## Minimal caster for tests: the stats and aim contract CastContext samples,
## with no FSM, faction or inventory attached.

var skill: int = 0
var speed: int = 0
var defence: int = 0

func get_aim_direction() -> Vector2:
	return Vector2.RIGHT
