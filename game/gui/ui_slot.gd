extends MarginContainer

@export var slot_texture: AtlasTexture

# YES THIS IS A REFERENCE, OBJECTS ARE PASSED BY REFERENCE!
var slot: GlobalInventory.Slot = null

static var _drag_source: MarginContainer = null
static var _drag_accepted: bool = false

func update_texture() -> void:
	if slot.item:
		$ItemTexture.texture = slot.item.icon
	else:
		$ItemTexture.texture = null

func _ready() -> void:
	if slot_texture:
		$SlotTexture.texture = slot_texture
	GlobalEvent.slot_updated.connect(_on_slot_updated)

func _get_drag_data(_position):
	if slot.item:
		var preview = TextureRect.new()
		preview.texture = slot.item.icon
		preview.custom_minimum_size = Vector2(8, 8)
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.position = -_position
		var wrapper = Control.new()
		wrapper.add_child(preview)
		set_drag_preview(wrapper)
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

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		if slot.item and slot.type == GlobalInventory.ItemType.BAG:
			var target = GlobalInventory.get_equipment_slot_for_item(slot.item)
			if target:
				GlobalInventory.swap_items(slot, target)

func _on_slot_updated(p_slot: GlobalInventory.Slot) -> void:
	if slot == p_slot:
		update_texture()
