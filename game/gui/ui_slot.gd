extends MarginContainer

const _FLATTEN_SHADER = preload("res://gui/flatten.gdshader")
const _SLOT_PX = 8
# Zughy 32 entries — cooldown overlays must stay in palette, so they only ever
# show these colors raw: no alpha blending, no modulate, no color tweens.
const _CURTAIN_COLOR = Color("302c2e")
const _FLASH_COLOR = Color("dff6f5")

@export var slot_texture: AtlasTexture

# YES THIS IS A REFERENCE, OBJECTS ARE PASSED BY REFERENCE!
# Binding a slot repaints immediately: slot_updated only fires on edits, so a slot
# bound to persisted inventory in a freshly loaded scene would otherwise stay blank.
var slot: GlobalInventory.Slot = null:
	set(value):
		slot = value
		if is_node_ready():
			update_texture()

static var _drag_source: MarginContainer = null
static var _drag_accepted: bool = false

static var _dither_texture: ImageTexture

var _curtain: TextureRect

func update_texture() -> void:
	if slot and slot.item:
		$ItemTexture.texture = slot.item.icon
	else:
		$ItemTexture.texture = null

func _ready() -> void:
	if slot_texture:
		$SlotTexture.texture = slot_texture
	GlobalEvent.slot_updated.connect(_on_slot_updated)
	GlobalEvent.spell_cooldown_started.connect(_on_spell_cooldown_started)
	set_process(false)

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
		_refresh_cooldown_overlay()

# --- Cooldown indicator ---
# A dithered dark curtain covers the icon and recedes top-to-bottom in whole
# pixel rows while the slot's spell cools down; the icon flashes when ready.
# Cooldowns belong to the spell resource, not the slot (see SpellCaster), so
# active cooldowns live in a table shared by all slots and each slot draws the
# curtain for whatever spell it currently holds — the overlay follows the
# spell when it's moved mid-cooldown.

static var _spell_cooldowns: Dictionary = {}  # SpellResource -> Vector2i(start_ms, end_ms)

func _on_spell_cooldown_started(spell: SpellResource, duration: float) -> void:
	if duration <= 0.0:
		return
	var now := Time.get_ticks_msec()
	_spell_cooldowns[spell] = Vector2i(now, now + int(duration * 1000))
	if slot and slot.item == spell:
		_show_curtain()

func _refresh_cooldown_overlay() -> void:
	if _has_active_cooldown():
		_show_curtain()
	elif _curtain:
		set_process(false)
		_curtain.hide()

# True when this slot's item is a spell still cooling down; prunes expired entries.
func _has_active_cooldown() -> bool:
	if slot == null or slot.item == null or not _spell_cooldowns.has(slot.item):
		return false
	if Time.get_ticks_msec() >= _spell_cooldowns[slot.item].y:
		_spell_cooldowns.erase(slot.item)
		return false
	return true

func _show_curtain() -> void:
	if not _curtain:
		_make_curtain()
	_curtain.show()
	set_process(true)

func _process(_delta: float) -> void:
	if not _has_active_cooldown():
		# Expiring while still displayed means the spell came off cooldown in
		# this slot — flash. (Item changes hide the curtain via slot_updated
		# before _process can run, so they never flash.)
		set_process(false)
		_curtain.hide()
		_flash_ready()
		return
	var entry: Vector2i = _spell_cooldowns[slot.item]
	var now := Time.get_ticks_msec()
	# Snap coverage to whole pixel rows so the curtain steps cleanly at 8x8.
	var rows := ceili(float(entry.y - now) / float(entry.y - entry.x) * _SLOT_PX)
	_curtain.position = Vector2(0, _SLOT_PX - rows)
	_curtain.size = Vector2(_SLOT_PX, rows)

func _make_curtain() -> void:
	if not _dither_texture:
		# 50% checkerboard of the palette dark — fakes transparency without
		# blending, so every pixel stays either the icon's or the palette dark.
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, _CURTAIN_COLOR)
		img.set_pixel(1, 1, _CURTAIN_COLOR)
		_dither_texture = ImageTexture.create_from_image(img)
	_curtain = TextureRect.new()
	_curtain.texture = _dither_texture
	_curtain.stretch_mode = TextureRect.STRETCH_TILE
	_curtain.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# Child of ItemTexture: escapes the MarginContainer's layout control and
	# draws above the icon.
	$ItemTexture.add_child(_curtain)

func _flash_ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = _FLATTEN_SHADER
	mat.set_shader_parameter("flat_color", _FLASH_COLOR)
	$ItemTexture.material = mat
	var tween := create_tween()
	tween.tween_interval(0.1)
	tween.tween_callback(func(): $ItemTexture.material = null)
