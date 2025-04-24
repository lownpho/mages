extends PanelContainer

@export var type: GlobalDefs.ItemType

var empty: bool = true
var holding_type: GlobalDefs.ItemType = GlobalDefs.ItemType.UNDEFINED
var item_texture = null
var dragging = false
var drag_preview = null

func set_item(texture: Texture2D, rcv_type: GlobalDefs.ItemType) -> void:
	empty = false
	holding_type = rcv_type
	item_texture = texture
	$TextureRect.texture = texture

func clear_item() -> void:
	empty = true
	item_texture = null
	$TextureRect.texture = null

func _get_drag_data(_position: Vector2):
	if empty:
		return null
		
	var preview = TextureRect.new()
	preview.texture = item_texture
	preview.custom_minimum_size = $TextureRect.custom_minimum_size
	
	var control = Control.new()
	control.add_child(preview)
	
	dragging = true
	GlobalEvent.drag_state_changed.emit(true)
	set_drag_preview(control)
	return self

func _can_drop_data(_position: Vector2, data) -> bool:
	if not (data is PanelContainer):
		return false
	return type == GlobalDefs.ItemType.UNDEFINED or data.holding_type == GlobalDefs.ItemType.UNDEFINED or type == data.holding_type

func _drop_data(_position: Vector2, data) -> void:
	if data == self:
		return
	
	var temp_texture = item_texture
	var temp_empty = empty
	var temp_type = holding_type
	
	if !data.empty:
		set_item(data.item_texture, data.holding_type)
	else:
		clear_item()
		
	if temp_empty:
		data.clear_item()
	else:
		data.set_item(temp_texture, temp_type)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and !event.pressed and dragging:
			dragging = false
			GlobalEvent.drag_state_changed.emit(false)
