extends Behaviour
class_name Guard

# A defensive windup beat: closes up, armouring itself while it can't act. Armour is a
# plain damage scale on the body, restored on exit so nothing leaks the reduction past
# this state. Guard is only ever entered because something already triggered engagement
# (proximity, a hit, or a pattern roll), so after duration it always hands off with no
# re-check — whatever comes next (a fixed attack, or the pattern dispatcher) is what
# decides if the fight is still on.

@export var done_state: String = "Pattern"
@export var duration: float = 1.4
@export var damage_scale: float = 0.35 ## Incoming damage while closed; <1 armours the bud.
@export var guard_anim: String = "guard"

var _timer: Timer

func _ready() -> void:
	super()
	_timer = creature.make_timer(func(): creature.fsm.transition_to(done_state))

func enter() -> void:
	creature.velocity = Vector2.ZERO
	creature.incoming_damage_scale = damage_scale
	creature.play(guard_anim)
	_timer.start(duration)

func exit() -> void:
	_timer.stop()
	creature.incoming_damage_scale = 1.0
