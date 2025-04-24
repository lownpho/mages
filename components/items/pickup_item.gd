extends Area2D

@export var type: GlobalDefs.ItemType
@export var item: PackedScene

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	GlobalEvent.item_added_to_inventory.connect(_on_item_added_to_inventory)

func _on_body_entered(_body: Node2D) -> void:
	GlobalEvent.item_picked_up.emit(name, type, item, $Sprite2D.texture)

func _on_item_added_to_inventory(node_name: String) -> void:
	if node_name == name:
		queue_free()
