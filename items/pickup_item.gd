extends Area2D

@export var item: ItemResource

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if item and item.icon:
		$Sprite2D.texture = item.icon

func _on_body_entered(_body: Node2D) -> void:
	var slot = GlobalInventory.bag_slots.add_at_first_empty(item)
	if slot:
		GlobalEvent.item_picked_up.emit(slot)
		queue_free()
