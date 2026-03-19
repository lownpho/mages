@tool
extends Area2D

@export var item: ItemResource: # Runs on assignment so the editor icon stays in sync.
	set(value):
		item = value
		_update_sprite()

func _ready() -> void:
	_update_sprite()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)

func _update_sprite() -> void:
	if not is_node_ready():
		return
	$Sprite2D.texture = item.icon if item and item.icon else null

func _on_body_entered(_body: Node2D) -> void:
	var slot = GlobalInventory.bag_slots.add_at_first_empty(item)
	if slot:
		GlobalEvent.item_picked_up.emit(slot)
		queue_free()
