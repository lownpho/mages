extends Area2D

@export var type: GlobalDefs.ItemType
@export var item: PackedScene

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(_body: Node2D) -> void:
	# Let's see if copy and reference hold here...
	var item_data = GlobalInventory.ItemData.new(type, item, $Sprite2D.texture)
	if GlobalInventory.add_item_to_bag(item_data):
		queue_free()
