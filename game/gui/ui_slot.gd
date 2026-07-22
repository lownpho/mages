extends MarginContainer

const _FLATTEN_SHADER = preload("res://gui/flatten.gdshader")
const _SLOT_PX = 8
# Zughy 32 entries — cooldown overlays must stay in palette, so they only ever
# show these colors raw: no alpha blending, no modulate, no color tweens.
const _CURTAIN_COLOR = Palette.BLACK
const _FLASH_COLOR = Palette.WHITE
const _GHOST_COLOR = Palette.GREY_DARK
const _DENY_COLOR = Palette.RED

# Tooltip stat icons: x offset of each 8x8 glyph in the y=8 row of ui.png.
const _UI = preload("res://gui/ui.png")
const _ICON_X = {
	"damage": 0, "cooldown": 8, "cast": 16,
	"health": 24, "defence": 40, "skill": 48, "speed": 56,
}

@export var slot_texture: AtlasTexture:
	set(value):
		slot_texture = value
		# Settable at runtime: the spell rows swap frames when SHIFT flips the
		# active page.
		if is_node_ready() and slot_texture:
			$SlotTexture.texture = slot_texture

# YES THIS IS A REFERENCE, OBJECTS ARE PASSED BY REFERENCE!
# Binding a slot repaints immediately: slot_updated only fires on edits, so a slot
# bound to persisted inventory in a freshly loaded scene would otherwise stay blank.
var slot: GlobalInventory.Slot = null:
	set(value):
		slot = value
		if is_node_ready():
			update_texture()
			# Rebinding (e.g. a spell-page flip) must also move the cooldown
			# curtain to whatever the slot now shows.
			_refresh_cooldown_overlay()

static var _drag_source: MarginContainer = null
static var _drag_accepted: bool = false

# --- Carry mode (click-click / controller swap) ---
# The device-agnostic sibling of drag & drop: activating a filled slot (LMB click
# or ui_accept on the focused slot) lifts its item — the source icon ghosts grey —
# and activating a second slot places/swaps it. Same slot or cancel returns it.
static var _carry_source: MarginContainer = null

static var _dither_texture: ImageTexture

var _curtain: TextureRect

static func carry_active() -> bool:
	return _carry_source != null

static func cancel_carry() -> void:
	if _carry_source:
		# Null first: _refresh_item_material re-applies the ghost for whoever is
		# still the carry source.
		var source := _carry_source
		_carry_source = null
		source._refresh_item_material()

func update_texture() -> void:
	if slot and slot.item:
		$ItemTexture.texture = slot.item.icon
		# Sentinel: Godot strips the tooltip text and skips the popup if it's blank,
		# so it must be non-whitespace; the value is unused, _make_custom_tooltip
		# builds the contents. Only arm it when there are bonuses to show, else the
		# empty tooltip would fall back to a bare "." popup.
		tooltip_text = "." if not slot.item.get_modifiers().is_empty() else ""
	else:
		$ItemTexture.texture = null
		tooltip_text = ""

# Returns only the stat grid — the wrapping popup wears the theme's TooltipPanel
# frame, so no panel needs building here.
func _make_custom_tooltip(_for_text: String) -> Object:
	var modifiers: Array = slot.item.get_modifiers()
	if modifiers.is_empty():
		return null
	return _stat_grid(modifiers)

func _stat_grid(rows: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 0)
	for row in rows:
		var icon := TextureRect.new()
		icon.texture = _stat_icon(row[0])
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(icon)
		var label := Label.new()
		label.text = row[1]
		label.custom_minimum_size = Vector2(10, 0)
		label.size_flags_horizontal = Control.SIZE_SHRINK_END
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(label)
	return grid

func _stat_icon(key: String) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = _UI
	t.region = Rect2(_ICON_X[key], 8, 8, 8)
	return t

func _ready() -> void:
	if slot_texture:
		$SlotTexture.texture = slot_texture
	GlobalEvent.slot_updated.connect(_on_slot_updated)
	GlobalEvent.spell_cooldown_started.connect(_on_spell_cooldown_started)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	GlobalInput.device_changed.connect(func(_pad: bool) -> void: queue_redraw())
	set_process(false)

# Focus ring for controller navigation only — mouse clicks also grab focus, but
# the cursor already shows where you are, so the ring would just linger there.
# Four edge lines hugging the frame with the corner pixels skipped, matching the
# slot art's rounded corners. MarginContainer never draws focus itself, so this
# is the slot's whole focus visual.
func _draw() -> void:
	if not has_focus() or not GlobalInput.using_gamepad:
		return
	draw_rect(Rect2(0, -1, size.x, 1), _FLASH_COLOR)
	draw_rect(Rect2(0, size.y, size.x, 1), _FLASH_COLOR)
	draw_rect(Rect2(-1, 0, 1, size.y), _FLASH_COLOR)
	draw_rect(Rect2(size.x, 0, 1, size.y), _FLASH_COLOR)

func _get_drag_data(_position):
	# A press already armed carry mode; a real drag supersedes it.
	cancel_carry()
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
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				# The first click of the pair armed carry — disarm before equipping.
				cancel_carry()
				_auto_equip()
			else:
				_activate()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_carry()
	elif event.is_action_pressed("ui_accept"):
		_activate()
		accept_event()
	elif event.is_action_pressed("ui_cancel"):
		# Only consume while carrying: an idle B/Esc must bubble up so the HUD
		# can exit slot navigation.
		if carry_active():
			cancel_carry()
			accept_event()
	elif event.is_action_pressed("discard"):
		_discard()
		accept_event()

func _auto_equip() -> void:
	if slot.item and slot.type == GlobalInventory.ItemType.BAG:
		var target = GlobalInventory.get_equipment_slot_for_item(slot.item)
		if target:
			GlobalInventory.swap_items(slot, target)

# One press = one step of the carry flow: lift, cancel (same slot), or place/swap.
func _activate() -> void:
	if _carry_source == null:
		if slot.item:
			_carry_source = self
			_refresh_item_material()
		return
	if _carry_source == self:
		cancel_carry()
		return
	var source: MarginContainer = _carry_source
	if source.slot.item == null:
		# The carried item vanished under us (e.g. console edit) — nothing to place.
		cancel_carry()
		return
	if slot.can_place_item(source.slot.item) and (not slot.item or source.slot.can_place_item(slot.item)):
		cancel_carry()
		GlobalInventory.swap_items(slot, source.slot)
	else:
		_flash_deny()

# Drops the carried item — or, when idle, this slot's item — onto the ground.
func _discard() -> void:
	var source: MarginContainer = _carry_source if _carry_source else self
	cancel_carry()
	if source.slot.item == null:
		return
	var dropped = source.slot.item
	source.slot.clear_item()
	GlobalEvent.item_dropped.emit(dropped)

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

func _flat_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _FLATTEN_SHADER
	mat.set_shader_parameter("flat_color", color)
	return mat

# The icon's steady-state material: grey ghost while this slot is the carry
# source, none otherwise. Flashes end by restoring through here so they can't
# wipe an active ghost.
func _refresh_item_material() -> void:
	$ItemTexture.material = _flat_material(_GHOST_COLOR) if _carry_source == self else null

func _flash_ready() -> void:
	$ItemTexture.material = _flat_material(_FLASH_COLOR)
	var tween := create_tween()
	tween.tween_interval(0.1)
	tween.tween_callback(_refresh_item_material)

# Invalid placement target: flash the frame red for a beat.
func _flash_deny() -> void:
	$SlotTexture.material = _flat_material(_DENY_COLOR)
	var tween := create_tween()
	tween.tween_interval(0.1)
	tween.tween_callback(func(): $SlotTexture.material = null)
