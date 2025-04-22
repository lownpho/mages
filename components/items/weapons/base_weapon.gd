extends Node2D
class_name BaseWeapon

@export var bullet_scene: PackedScene
@export var fire_cooldown: float = 0.5
@export var mana_cost: int = 1

var can_fire: bool = true
var fire_timer: Timer

func _ready() -> void:
	fire_timer = Timer.new()
	fire_timer.one_shot = true
	fire_timer.wait_time = fire_cooldown
	fire_timer.timeout.connect(_on_fire_timer_timeout)
	add_child(fire_timer)

func spawn_bullet(direction: Vector2, skill: int) -> void:
	var bullet = bullet_scene.instantiate()
	bullet.position = global_position
	bullet.base_direction = direction
	bullet.skill = skill
	get_tree().root.add_child(bullet)

func _on_fire_timer_timeout() -> void:
	can_fire = true

func set_cooldown(time: float) -> void:
	fire_cooldown = time
	fire_timer.wait_time = time
