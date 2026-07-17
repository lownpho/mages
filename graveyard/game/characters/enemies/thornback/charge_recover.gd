extends Behaviour
class_name ChargeRecover

# The punish window. After a dash the charger is rooted for recover_time, playing the
# spent animation — this is when it dies. When it expires it re-engages: still sees the
# target → back to the wind-up; otherwise → idle.

@export var detect_probe_path: NodePath
@export var windup_state: String = "Windup"
@export var idle_state: String = "Idle"
@export var recover_time: float = 1.2
@export var recover_anim: String = "recover"

@onready var _detect: RayCast2D = get_node(detect_probe_path)
var _timer: Timer

func _ready() -> void:
	super()
	_timer = creature.make_timer(_on_recovered)

func enter() -> void:
	_detect.enabled = true
	creature.velocity = Vector2.ZERO
	creature.play(recover_anim)
	_timer.start(recover_time)

func exit() -> void:
	_detect.enabled = false
	_timer.stop()

func _on_recovered() -> void:
	if creature.look_for_target(_detect):
		creature.fsm.transition_to(windup_state)
	else:
		creature.fsm.transition_to(idle_state)
