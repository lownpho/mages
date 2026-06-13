@tool
extends Area2D

signal hurt(damage: int)

@export var radius: float = 8.0:
	set(value):
		radius = value
		_update_shape()

func _ready() -> void:
	_update_shape()
	body_entered.connect(_on_hit)
	area_entered.connect(_on_hit)

func _update_shape() -> void:
	var shape_node := get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape is CircleShape2D:
		shape_node.shape.radius = radius

# Damage sources are bullet bodies or damage areas (e.g. spell AoEs);
# both carry their damage via get_damage().
func _on_hit(node: Node2D) -> void:
	var damage = 0

	if node.has_method("get_damage"):
		damage = node.get_damage()
		emit_signal("hurt", damage)
		GlobalEvent.entity_damaged.emit(owner if owner else get_parent(), damage, node)
	else:
		print("Node has no get_damage method! Node name: ", node.name)

	 # This logic should be in the bullet
	if node.is_in_group("bullets"):
		node.reached_hurtbox()
