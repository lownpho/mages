extends Chase
class_name WeaveChase

@export var weave_frequency: float = 2.0 ## Sideways oscillation rate.
@export var weave_amplitude: float = 1.3 ## Sway strength relative to forward speed.

var _weave_time: float = 0.0
var _weave_phase: float = 0.0
var _weave_retarget: float = 0.0

func enter() -> void:
	_weave_time = 0.0
	_weave_retarget = 0.0
	super()

func _velocity(to_player: Vector2, delta: float) -> Vector2:
	_weave_time += delta
	_weave_retarget -= delta
	# Re-roll the phase at random intervals so the weave reads as quick and
	# unpredictable rather than a clean, readable sine.
	if _weave_retarget <= 0.0:
		_weave_retarget = randf_range(0.3, 0.9)
		_weave_phase = randf_range(-PI, PI)
	var forward := to_player.normalized()
	var perp := Vector2(-forward.y, forward.x)
	var sway := sin(_weave_time * weave_frequency + _weave_phase) * weave_amplitude
	return (forward + perp * sway) * speed
