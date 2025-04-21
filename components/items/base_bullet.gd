extends CharacterBody2D

const DEFAULT_DIRECTION = Vector2.UP

# Set by the parent, find a better way to do this
var speed: float
var damage: int
var lifetime: float
var direction: Vector2

var lifetime_timer: Timer

@onready var initial_position = position

func _ready() -> void:
	lifetime_timer = Timer.new()
	lifetime_timer.one_shot = true
	lifetime_timer.wait_time = lifetime
	lifetime_timer.autostart = true
	lifetime_timer.timeout.connect(_on_lifetime_timeout)
	add_child(lifetime_timer)
	
	velocity = direction * speed

func _physics_process(delta: float) -> void:
	var collision = move_and_collide(velocity * delta)
	
	if collision:
		# Add effects or damage logic here
		queue_free()

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()

func _on_lifetime_timeout() -> void:
	queue_free()

func get_damage() -> int:
	return damage
