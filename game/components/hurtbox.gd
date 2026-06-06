@tool
extends Area2D

signal hurt(damage: int)

@export var radius: float = 8.0:
	set(value):
		radius = value
		_update_shape()

func _ready() -> void:
	_update_shape()
	body_entered.connect(_on_body_entered)

func _update_shape() -> void:
	var shape_node := get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape is CircleShape2D:
		shape_node.shape.radius = radius

func _on_body_entered(body: Node2D) -> void:
	var damage = 0
	
	if body.has_method("get_damage"):
		damage = body.get_damage()
		emit_signal("hurt", damage)
	else:
		print("Body has no get_damage method! Body name: ", body.name)
		
	 # This logic should be in the bullet
	if body.is_in_group("bullets"):
		body.reached_hurtbox()
