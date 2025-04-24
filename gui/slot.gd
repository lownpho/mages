extends PanelContainer

var empty: bool = true
var item_texture = null
var dragging = false
var drag_preview = null

func set_item(texture: Texture2D) -> void:
	empty = false
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
	# This is going to change to accomodate multiple item types
	return data is PanelContainer

func _drop_data(_position: Vector2, data) -> void:
	if data == self:
		return
		
	# Swap items between slots
	var temp_texture = item_texture
	var temp_empty = empty
	
	if !data.empty:
		set_item(data.item_texture)
	else:
		clear_item()
		
	if temp_empty:
		data.clear_item()
	else:
		data.set_item(temp_texture)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and !event.pressed and dragging:
			dragging = false
			GlobalEvent.drag_state_changed.emit(false)
