extends Hold
class_name Wander

# A Hold that drifts: same clock, detection and hand-off, but it picks a random heading on
# entry and walks it until the timer lapses.

@export var speed: float = 12.0

var _dir: Vector2 = Vector2.ZERO

func enter() -> void:
	_dir = Vector2.from_angle(randf() * TAU)
	super()

func _tick(_delta: float) -> void:
	creature.velocity = _dir * speed
	creature.move_and_slide()
	creature.face(_dir.x)
