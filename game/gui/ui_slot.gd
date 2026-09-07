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
# Wrap column for the tooltip blurb, in the 320x180 content scale.
const _BLURB_WIDTH = 40
const _ICON_X = {
	"damage": 0, "cooldown": 8, "cast": 16,
	"health": 24, "defence": 40, "skill": 48, "speed": 56,
}

@export var slot_texture: AtlasTexture:
	set(value):
		slot_texture = value
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
			# Rebinding must also move the cooldown curtain to whatever the slot now shows.
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
	$ItemTexture.texture = slot.item.icon if slot and slot.item else null

func _blurb() -> String:
	return (slot.item as SpellResource).blurb if slot.item is SpellResource else ""

func _has_tooltip() -> bool:
	return not slot.item.get_modifiers().is_empty() or not _blurb().is_empty()

# The stat grid with the blurb line under it; null when the item has nothing to
# say, which keeps the tip shut.
func _tooltip_content() -> Control:
	if not _has_tooltip():
		return null
	var modifiers: Array = slot.item.get_modifiers()
	var blurb := _blurb()
	if blurb.is_empty():
		return _stat_grid(modifiers)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	if not modifiers.is_empty():
		var grid := _stat_grid(modifiers)
		# The blurb sets the panel's width, so the narrower stat block would otherwise sit
		# left of it; centre the block while the blurb under it stays left justified.
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(grid)
	var label := Label.new()
	label.text = blurb
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# The theme's 3px gap is sized for prose, not an 8px pixel font in a tooltip.
	label.add_theme_constant_override("line_spacing", 0)
	# Autowrap leaves the label's minimum width at one word, so the panel would
	# shrink to that — this is what fixes the tooltip's wrap column.
	label.custom_minimum_size = Vector2(_BLURB_WIDTH, 0)
	box.add_child(label)
	return box

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
	focus_entered.connect(_refresh_focus_visuals)
	focus_exited.connect(_refresh_focus_visuals)
	GlobalInput.device_changed.connect(func(_pad: bool) -> void: _refresh_focus_visuals())
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
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

# --- Tooltip ---
# Godot's own hover tooltip is not used. It pops where the cursor is, which across a grid of
# 8px slots means a dozen different spots — most of them on top of the strip the tip is
# describing, and none of them where your eye already is. So mouse hover and pad focus both
# raise this panel instead, parked beside the strip and level with the panel of items it is
# describing: a tip lands on empty screen, covers nothing, and doesn't jump as you walk the slots.
# One tip exists at a time, hence the statics.

static var _tip: PanelContainer = null
static var _tip_owner: MarginContainer = null

# Gap between the strip's right edge and the tip.
const _TIP_MARGIN = 2

var _hovered: bool = false

static func _hide_tip() -> void:
	# Statics outlive the scene the tip was parented into, so never trust the reference.
	if is_instance_valid(_tip):
		_tip.queue_free()
	_tip = null
	_tip_owner = null

func _on_mouse_entered() -> void:
	_hovered = true
	_refresh_tip()

func _on_mouse_exited() -> void:
	_hovered = false
	_refresh_tip()

## Focus ring and the pad's tip both follow "focused AND on a pad", so they move together.
func _refresh_focus_visuals() -> void:
	queue_redraw()
	_refresh_tip()

## Hover raises the tip on mouse and keyboard; focus raises it on a pad. The cursor already
## shows where you are on a mouse, so a parked focus there would just leave a tip behind.
func _wants_tip() -> bool:
	return has_focus() if GlobalInput.using_gamepad else _hovered

func _refresh_tip() -> void:
	if _wants_tip():
		_show_tip()
	elif _tip_owner == self:
		_hide_tip()

func _show_tip() -> void:
	_hide_tip()
	if slot == null or slot.item == null:
		return
	var content := _tooltip_content()
	if content == null:
		return   # nothing to say — a bare item keeps the tip shut
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"TooltipPanel"
	panel.add_child(content)
	# Parented to the CanvasLayer, not the strip: inside the layout it would be clipped and would
	# reflow the slot grid around it. Added last, so it draws over the strip — which is why no
	# slot part may carry a z_index, or it would punch back through the tip (see slot.tscn).
	var layer := _ui_layer()
	if layer == null:
		panel.queue_free()
		return   # a slot mounted outside a CanvasLayer (debug scenes) has nowhere to put it
	layer.add_child(panel)
	panel.global_position = _tip_position(panel.get_combined_minimum_size())
	_tip = panel
	_tip_owner = self

# The parking spot: clear of the strip's right edge, level with the panel the slot sits in — the
# spells panel for a spell tip, the bag for a bag tip. Neither the strip (stretched to the full
# screen height) nor the column (starts up at the minimap) says where the items are, so anchoring
# to either left the tip floating above the icons it describes. One spot per panel still means the
# tip holds still while you walk that panel's slots. The strip hugs the left screen edge, so there
# is always room that way, and clamping only guards a tip too tall or too wide for what's left.
# Falls back to hugging the slot when there is no strip to measure.
func _tip_position(tip_size: Vector2) -> Vector2:
	var strip := _strip()
	var pos := global_position + Vector2(size.x + _TIP_MARGIN, 0.0)
	if strip:
		var anchor := _item_panel()
		pos = Vector2(strip.global_position.x + strip.size.x + _TIP_MARGIN,
				anchor.global_position.y if anchor else global_position.y)
	var room := get_viewport_rect().size - tip_size
	return Vector2(clampf(pos.x, 0.0, maxf(0.0, room.x)), clampf(pos.y, 0.0, maxf(0.0, room.y)))

# The framed panel holding this slot's grid — the spells panel or the bag. Null for a slot mounted
# bare, which then anchors on itself.
func _item_panel() -> Control:
	var n: Node = get_parent()
	while n != null and not (n is CanvasLayer):
		if n is PanelContainer:
			return n
		n = n.get_parent()
	return null

# The strip is the slot's outermost Control ancestor inside the CanvasLayer.
func _strip() -> Control:
	var strip: Control = null
	var n: Node = get_parent()
	while n != null and not (n is CanvasLayer):
		if n is Control:
			strip = n
		n = n.get_parent()
	return strip if n != null else null

func _ui_layer() -> CanvasLayer:
	var n: Node = get_parent()
	while n != null and not (n is CanvasLayer):
		n = n.get_parent()
	return n as CanvasLayer

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
	return GlobalInventory.can_equip(data.slot.item, slot, data.slot) \
		and (not slot.item or GlobalInventory.can_equip(slot.item, data.slot, slot))

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
			_activate()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_carry()
		# A mouse click grabs focus same as pad navigation would, but keyboard/mouse play
		# never means to leave it parked here — ui_accept (Space) shares its key with cast4,
		# so a stale focused slot would silently eat the next spell cast instead of casting it.
		if not GlobalInput.using_gamepad:
			release_focus()
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
	if GlobalInventory.can_equip(source.slot.item, slot, source.slot) \
		and (not slot.item or GlobalInventory.can_equip(slot.item, source.slot, slot)):
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
		# An item swapped into or out of the shown slot changes what the tip should say.
		_refresh_focus_visuals()

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
