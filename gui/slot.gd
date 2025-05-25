extends PanelContainer

@export var type: GlobalDefs.ItemType

var item: GlobalInventory.ItemData = null
# It's ugly but this will be set when the ui is ready, so it's guaranteed to be valid
var slot_position: GlobalInventory.SlotPosition = null

func update(slot: GlobalInventory.SlotPosition) -> void:
	item = GlobalInventory.get_item_at(slot)
	if item:
		$TextureRect.texture = item.texture
	else:
		$TextureRect.texture = null

func _get_drag_data(_position):
	if item:
		var preview = TextureRect.new()
		preview.texture = $TextureRect.texture
		set_drag_preview(preview)
	return slot_position

func _can_drop_data(_position, data):
	# Data is the slot we are dropping from
	var candidate_item = GlobalInventory.get_item_at(data)
	# Here we forbid the drop of an empty item into a slot
	return candidate_item and GlobalInventory.can_place_item(candidate_item, slot_position)
 
func _drop_data(_position, data):
	# position is some coordinates...
	# Data is the slot we are dropping from
	if GlobalInventory.swap_bag_and_active(slot_position, data):
		pass
	else:
		GlobalInventory.swap_items(data, slot_position)
