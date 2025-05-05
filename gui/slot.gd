extends PanelContainer

@export var type: GlobalDefs.ItemType

var item: GlobalInventory.ItemData = null
var item_position: GlobalInventory.SlotPosition = null

func update(slot_position: GlobalInventory.SlotPosition) -> void:
	item = GlobalInventory.get_item_at(slot_position)
	print("slot ", name, " updated with item ", item)
	if item:
		$TextureRect.texture = item.texture
	else:
		$TextureRect.texture = null

func _get_drag_data(_position):
	if item_position:
		print("Drag data: type ", item_position.type, " idx ", item_position.index)
		var preview = TextureRect.new()
		preview.texture = $TextureRect.texture
		set_drag_preview(preview)
		return item_position
	else:
		print("Drag data is null")
	return null

func _can_drop_data(_position, data):
	#  type == GlobalInventory.get_item_at(data).type if GlobalInventory.get_item_at(data) else true
	# return data is GlobalInventory.ItemData
	if data:
		print("can drop data? type ", data.type, " idx ", data.index)
	else:
		print("can drop data? null")
	return true

func _drop_data(_position, data):
	if data:
		print("Dropping data (dst): type ", data.type, " idx ", data.index)
		print("Dropping data (src): type ", item_position.type, " idx ", item_position.index)
		GlobalInventory.swap_items(item_position, data)
	else:
		print("Dropping data is null")
