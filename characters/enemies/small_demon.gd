extends CharacterBody2D

@export var max_health: int = 100  # Maximum health value
var health: int  # Current health

@onready var hurtbox = $Hurtbox

func _ready() -> void:
	health = max_health  # Initialize health to max value
	hurtbox.hurt.connect(_on_hurt)
	
func _physics_process(delta: float) -> void:
	move_and_slide()

func _on_hurt(damage: int) -> void:
	health -= damage
	print("hurt: ", damage, " health: ", health)
	
	if health <= 0:
		die()

func die() -> void:
	queue_free()  # Remove enemy from scene
