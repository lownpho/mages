extends Behaviour
class_name Idle

@export var detect_probe_path: NodePath
@export var alert_state: String = "Chase"
@export var next_state: String = "Wander"
@export var min_time: float = 1.5
@export var max_time: float = 4.0

@onready var _detect: RayCast2D = get_node(detect_probe_path)
var _timer: Timer

func _ready() -> void:
	super()
	_timer = enemy.make_timer(func(): enemy.fsm.transition_to(next_state))

func enter() -> void:
	_detect.enabled = true
	enemy.velocity = Vector2.ZERO
	_timer.start(randf_range(min_time, max_time))
	enemy.play("idle")

func exit() -> void:
	_detect.enabled = false
	_timer.stop()

func physics_update(_delta: float) -> void:
	if enemy.look_for_player(_detect):
		enemy.fsm.transition_to(alert_state)
