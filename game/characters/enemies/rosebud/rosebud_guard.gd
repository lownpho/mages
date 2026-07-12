extends Behaviour
class_name RosebudGuard

# The windup beat before blooming: the bud closes up (guard pose), armouring itself while
# it can't fire. Armour is a plain damage scale on the body, restored on exit so nothing
# leaks the reduction past this state. Guard is only ever entered because something already
# triggered engagement (proximity or a hit), so after guard_time it always blooms into
# attack_state with no re-check — Attack's own no-range-gate volley is what decides when
# the fight is actually over.

@export var attack_state: String = "Attack"
@export var guard_time: float = 1.4
@export var damage_scale: float = 0.35 ## Incoming damage while closed; <1 armours the bud.
@export var guard_anim: String = "guard"

var _timer: Timer

func _ready() -> void:
	super()
	_timer = creature.make_timer(func(): creature.fsm.transition_to(attack_state))

func enter() -> void:
	creature.velocity = Vector2.ZERO
	creature.incoming_damage_scale = damage_scale
	creature.play(guard_anim)
	_timer.start(guard_time)

func exit() -> void:
	_timer.stop()
	creature.incoming_damage_scale = 1.0
