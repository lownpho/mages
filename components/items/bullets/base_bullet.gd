extends CharacterBody2D
class_name BaseBullet

@export var base_damage: float = 1
@export var distance: int = 16
@export var speed: int = 128
@export var skill_scaling: float = 1

var base_direction: Vector2 = Vector2.UP
var lifetime_timer: Timer = null
var skill: int = 0

@onready var initial_position = position

func _ready() -> void:
	lifetime_timer = Timer.new()
	lifetime_timer.one_shot = true
	lifetime_timer.wait_time = float(distance) / speed
	lifetime_timer.autostart = true
	lifetime_timer.timeout.connect(_on_lifetime_timeout)
	add_child(lifetime_timer)
	
	velocity = base_direction * speed

func _physics_process(delta: float) -> void:
	var collision = move_and_collide(velocity * delta)
	
	if collision:
		queue_free()

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()

func _on_lifetime_timeout() -> void:
	queue_free()

func get_damage() -> int:
	return round(base_damage + skill * skill_scaling)
