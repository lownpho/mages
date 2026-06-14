extends Behaviour
class_name Idle

@export var detect_probe_path: NodePath
@export var alert_state: String = "Chase"
@export var next_state: String = "Wander"
@export var min_time: float = 1.5
@export var max_time: float = 4.0
@export var idle_anim: String = "idle" ## Played while idling; override for art with different tag names.

@onready var _detect: RayCast2D = get_node(detect_probe_path)
var _timer: Timer

func _ready() -> void:
	super()
	_timer = creature.make_timer(func(): creature.fsm.transition_to(next_state))

func enter() -> void:
	_detect.enabled = true
	creature.velocity = Vector2.ZERO
	_timer.start(randf_range(min_time, max_time))
	creature.play(idle_anim)

func exit() -> void:
	_detect.enabled = false
	_timer.stop()

func physics_update(_delta: float) -> void:
	if creature.look_for_target(_detect):
		creature.fsm.transition_to(alert_state)
