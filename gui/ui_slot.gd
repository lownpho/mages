extends PanelContainer

# YES THIS IS A REFERENCE, OBJECTS ARE PASSED BY REFERENCE!
var slot: GlobalInventory.Slot = null

static var _drag_source: PanelContainer = null
static var _drag_accepted: bool = false

func update_texture() -> void:
	if slot.item:
		$TextureRect.texture = slot.item.icon
	else:
		$TextureRect.texture = null

func _ready() -> void:
	GlobalEvent.slot_updated.connect(_on_slot_updated)

func _get_drag_data(_position):
	if slot.item:
		var preview = TextureRect.new()
		preview.texture = slot.item.icon
		set_drag_preview(preview)
		_drag_source = self
		_drag_accepted = false
		return self
	return null

func _can_drop_data(_position, data) -> bool:
	return slot.can_place_item(data.slot.item) and (not slot.item or data.slot.can_place_item(slot.item))

func _drop_data(_position, data) -> void:
	_drag_accepted = true
	if slot.item:
		GlobalInventory.swap_items(slot, data.slot)
	else:
		slot.set_item(data.slot.item)
		data.slot.clear_item()
	data.update_texture()
	update_texture()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drag_source == self and not _drag_accepted:
		var dropped_item = slot.item
		slot.clear_item()
		update_texture()
		GlobalEvent.item_dropped.emit(dropped_item)
		_drag_source = null

func _on_slot_updated(p_slot: GlobalInventory.Slot) -> void:
	if slot == p_slot:
		update_texture()
