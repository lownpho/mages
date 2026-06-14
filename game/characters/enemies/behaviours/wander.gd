extends Behaviour
class_name Wander

@export var detect_probe_path: NodePath
@export var alert_state: String = "Chase"
@export var next_state: String = "Idle"
@export var speed: float = 12.0
@export var min_time: float = 0.4
@export var max_time: float = 1.2

@onready var _detect: RayCast2D = get_node(detect_probe_path)
var _timer: Timer
var _dir: Vector2 = Vector2.ZERO

func _ready() -> void:
	super()
	_timer = enemy.make_timer(func(): enemy.fsm.transition_to(next_state))

func enter() -> void:
	_detect.enabled = true
	_dir = Vector2.from_angle(randf() * TAU)
	_timer.start(randf_range(min_time, max_time))
	enemy.play("run")

func exit() -> void:
	_detect.enabled = false
	_timer.stop()

func physics_update(_delta: float) -> void:
	if enemy.look_for_target(_detect):
		enemy.fsm.transition_to(alert_state)
		return
	enemy.velocity = _dir * speed
	enemy.move_and_slide()
	enemy.face(_dir.x)
