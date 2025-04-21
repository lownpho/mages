extends Node2D

@export var bullet_scene: PackedScene
@export var bullet_config: BulletConfig
@export var fire_cooldown: float = 0.5
@export var power_scaling: float = 1

var can_fire: bool = true
var fire_timer: Timer

func _ready() -> void:
	fire_timer = Timer.new()
	fire_timer.one_shot = true
	fire_timer.wait_time = fire_cooldown
	fire_timer.timeout.connect(_on_fire_timer_timeout)
	add_child(fire_timer)

func fire(direction: Vector2, power: int) -> void:
	if not can_fire or not bullet_scene:
		return
		
	var bullet = bullet_scene.instantiate()
	configure_bullet(bullet, power)
	bullet.position = global_position
	bullet.direction = direction
	
	get_tree().root.add_child(bullet)

	can_fire = false
	fire_timer.start()

func configure_bullet(bullet: Node2D, power: int) -> void:
	if not bullet_config:
		print("No bullet configuration set!")
		return
		
	bullet.damage = bullet_config.damage + power_scaling * power
	bullet.distance = bullet_config.distance
	bullet.speed = bullet_config.speed
	bullet.collision_layer = bullet_config.collision_layer

func _on_fire_timer_timeout() -> void:
	can_fire = true

func set_cooldown(time: float) -> void:
	fire_cooldown = time
	fire_timer.wait_time = time
