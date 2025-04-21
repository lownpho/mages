extends Node2D

@export var bullet_scene: PackedScene
@export var fire_cooldown: float = 0.5

@export var bullet_speed: float = 200.0
@export var range: float = 128.0
@export var bullet_damage: int = 10

var bullet_lifetime: float = range / bullet_speed

var can_fire: bool = true
var fire_timer: Timer

func _ready() -> void:
	fire_timer = Timer.new()
	fire_timer.one_shot = true
	fire_timer.wait_time = fire_cooldown
	fire_timer.timeout.connect(_on_fire_timer_timeout)
	add_child(fire_timer)

func fire(direction: Vector2) -> void:
	if not can_fire or not bullet_scene:
		return
		
	var bullet = bullet_scene.instantiate()
	bullet.damage = bullet_damage
	bullet.lifetime = bullet_lifetime
	bullet.speed = bullet_speed

	# Player bullet layer
	# Done here because the bullets it's instanced in code
	bullet.collision_layer |= 1 << 8

	bullet.position = position
	bullet.direction = direction.normalized()
	
	add_child(bullet)

	can_fire = false
	fire_timer.start()

func _on_fire_timer_timeout() -> void:
	can_fire = true

func set_cooldown(time: float) -> void:
	fire_cooldown = time
	fire_timer.wait_time = time

func set_bullet_speed(speed: float) -> void:
	bullet_speed = speed
