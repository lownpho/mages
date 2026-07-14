extends Behaviour
class_name Blink

# Vanish for a beat, then reappear at a random offset around the target — the
# teleport that resets an engagement (shade after each volley, elder stalker between
# patterns). No firing here; hands straight back once relocated.

@export var duration: float = 0.35 ## Vanish time before the jump lands.
@export var min_dist: float = 40.0
@export var max_dist: float = 90.0
@export var done_state: String = "Volley"
@export var blink_anim: String = "blink"

var _timer: Timer

func _ready() -> void:
	super()
	_timer = creature.make_timer(_finish)

func enter() -> void:
	creature.velocity = Vector2.ZERO
	creature.play(blink_anim)
	_timer.start(duration)

func exit() -> void:
	_timer.stop()

func _finish() -> void:
	var target := creature.get_target()
	if target:
		var angle := randf() * TAU
		var dist := randf_range(min_dist, max_dist)
		creature.global_position = target.global_position + Vector2.from_angle(angle) * dist
	creature.fsm.transition_to(done_state)
