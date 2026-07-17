extends Behaviour
class_name ChargeWindup

# A charger's telegraph: plant, face the target, and hold the wind-up animation for
# windup_time before committing to the dash. Once entered it always reaches the dash —
# the wind-up IS the tell, so it can't be cancelled by the player slipping out of range.
# It only tracks facing; the dash re-aims at the target the instant it launches, so the
# counterplay is to sidestep as it commits (and the dash can't corner once moving).

@export var dash_state: String = "Dash"
@export var windup_time: float = 0.8
@export var windup_anim: String = "windup"

var _timer: Timer

func _ready() -> void:
	super()
	_timer = creature.make_timer(func(): creature.fsm.transition_to(dash_state))

func enter() -> void:
	creature.velocity = Vector2.ZERO
	creature.play(windup_anim)
	_timer.start(windup_time)

func exit() -> void:
	_timer.stop()

func physics_update(_delta: float) -> void:
	var target := creature.get_target()
	if target:
		creature.face(target.global_position.x - creature.global_position.x)
