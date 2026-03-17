extends PanelContainer

# YES THIS IS A REFERENCE, OBJECTS ARE PASSED BY REFERENCE!
var slot: GlobalInventory.Slot = null

func update_texture() -> void:
	if slot.item:
		$TextureRect.texture = slot.item.texture
	else:
		$TextureRect.texture = null

func _ready() -> void:
	GlobalEvent.item_picked_up.connect(_on_item_pickup)

func _get_drag_data(_position):
	if slot.item:
		var preview = TextureRect.new()
		preview.texture = slot.item.texture
		set_drag_preview(preview)
		return self
	return null

func _can_drop_data(_position, data) -> bool:
	return slot.can_place_item(data.slot.item) and (not slot.item or data.slot.can_place_item(slot.item))

func _drop_data(_position, data) -> void:
	if slot.item:
		GlobalInventory.swap_items(slot, data.slot)
	else:
		slot.set_item(data.slot.item)
		data.slot.clear_item()
	data.update_texture()
	update_texture()

func _on_item_pickup(p_slot: GlobalInventory.Slot) -> void:
	if slot == p_slot:
		update_texture()
