@tool
extends Area2D

signal hurt(damage: int, source: Node)

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
		# The shape is a sub-resource shared across every Hurtbox instance;
		# duplicate before mutating so instances don't trample each other's radius.
		if not shape_node.shape.resource_local_to_scene:
			shape_node.shape = shape_node.shape.duplicate()
			shape_node.shape.resource_local_to_scene = true
		shape_node.shape.radius = radius

# Damage sources are bullet bodies or damage areas (e.g. spell AoEs);
# both carry their damage via get_damage(). We hand the raw damage and the source
# to the victim and let *it* report entity_damaged — mitigation (defence, shields)
# is victim-specific, so only the victim knows the damage actually taken.
func _on_hit(node: Node2D) -> void:
	if node.has_method("get_damage"):
		hurt.emit(node.get_damage(), node)
	else:
		print("Node has no get_damage method! Node name: ", node.name)

	 # This logic should be in the bullet
	if node.is_in_group("bullets"):
		node.reached_hurtbox()
