extends Behaviour
class_name TimedChase

# Boss pattern: bear down on the target for a fixed window, then hand back to the
# dispatcher. No probes — like the rest beat, the fight is already committed once a
# pattern rolls, so losing line of sight mid-pursuit shouldn't abort the pressure.

@export var duration: float = 4.0
@export var speed: float = 40.0
@export var done_state: String = "Pattern"
@export var run_anim: String = "run"

var _timer: Timer

func _ready() -> void:
	super()
	_timer = creature.make_timer(func(): creature.fsm.transition_to(done_state))

func enter() -> void:
	creature.play(run_anim)
	_timer.start(duration)

func exit() -> void:
	_timer.stop()
	creature.velocity = Vector2.ZERO

func physics_update(_delta: float) -> void:
	var target := target_or_go(done_state)
	if not target:
		return
	if _reached(target):
		go_to(_reached_state())
		return
	var to_target := target.global_position - creature.global_position
	creature.face(to_target.x)
	creature.velocity = to_target.normalized() * speed
	creature.move_and_slide()

# Override point: subclasses that should stop chasing early (e.g. once within a
# pattern's own attack range) hook in here instead of duplicating physics_update.
func _reached(_target: Node2D) -> bool:
	return false

# Where arriving hands off. Timing out and losing the target both mean the pursuit
# failed and belong back at the dispatcher, so only a subclass that can actually
# arrive has a second destination to offer.
func _reached_state() -> String:
	return done_state
