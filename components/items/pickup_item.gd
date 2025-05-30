extends Area2D

@export var type: GlobalInventory.ItemType
@export var item: PackedScene

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(_body: Node2D) -> void:
	# Let's see if copy and reference hold here...
	var item_data = GlobalInventory.ItemData.new(type, item, $Sprite2D.texture)
	var slot = GlobalInventory.bag_slots.add_at_first_empty(item_data)
	if slot:
		GlobalEvent.item_picked_up.emit(slot)
		queue_free()
