extends Behaviour
class_name FaeRest

# Stops and does nothing for a beat: the burn window between patterns. A plain timed
# hold, no detection — the fight is already committed once the boss is engaged.

@export var duration: float = 2.5
@export var done_state: String = "Pattern"
@export var rest_anim: String = "rest"

var _timer: Timer

func _ready() -> void:
	super()
	_timer = creature.make_timer(func(): creature.fsm.transition_to(done_state))

func enter() -> void:
	creature.velocity = Vector2.ZERO
	creature.play(rest_anim)
	_timer.start(duration)

func exit() -> void:
	_timer.stop()
