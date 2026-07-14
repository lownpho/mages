extends Node2D
## Combat Lab — the balance/testing playground that replaced the hand-authored test_arena.
## Everything is generated at runtime by scanning the content folders, so new items and
## enemies appear here automatically:
##
##   Tab          toggle the lab panel (the game pauses while it is open)
##   panel open   LMB on the arena places the selected enemy brush, RMB removes the
##                nearest enemy; item icons: LMB equips, RMB drops as a real pickup
##   F3           damage overlay (dealt/taken tallies), ` console (give/spawn/tp/...)
##
## Cheats: god mode, stat overrides (applied as a player buff), heal.
## "Kill all" runs real deaths (drops + bestiary count!); "Clear" silently despawns.
## "Reload .tres" re-reads every slotted item from disk — tune stats in a text editor
## and click it, no restart. Panel/cheat state persists across runs (user://debug_state.cfg).

const PANEL_W := 118.0
const FLOOR_HALF_TILES := 40          ## generated floor half-extent, in tiles
const DUMMY_ID := &"dummy"
const LabDummy := preload("res://debug/combat_lab/lab_dummy.gd")
const PLACEHOLDER_SCENE := preload("res://debug/placeholder/placeholder.tscn")

@onready var _player: CharacterBody2D = $Entities/Player
@onready var _enemies: Node2D = $Entities/Enemies
@onready var _pickups: Node2D = $Pickups
@onready var _floor: TileMapLayer = $Floor
@onready var _lab_ui: CanvasLayer = $LabUI

var _panel: PanelContainer
var _tabs: TabContainer
var _hint: Label
var _brush: StringName = DUMMY_ID
var _brush_buttons: Dictionary = {}    ## enemy id -> Button, for highlight
var _freeze := false
var _god := false
var _dummy_hp := 0
var _dummy_def := 0
var _cheat_buff := ItemResource.new()  ## stat overrides ride the player's buff pipeline


func _ready() -> void:
	_player.debug_never_die = true
	_build_floor()
	_restore_state()
	_build_ui()
	_apply_god()
	_set_panel_open(false)


# _input (not _unhandled) so Tab still toggles when a panel control holds keyboard focus —
# the GUI would otherwise consume Tab for focus navigation.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_TAB:
		_set_panel_open(not _panel.visible)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and _panel.visible:
		_set_panel_open(false)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _panel.visible:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_spawn_brush(get_global_mouse_position())
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_despawn_nearest(get_global_mouse_position())


# --- Arena ------------------------------------------------------------------------------

## Fill a big square of floor from the tileset's own tiles (probability-weighted), so the
## arena floor looks like real ground without a hand-painted tilemap in the scene file.
func _build_floor() -> void:
	var ts := _floor.tile_set
	if ts == null or ts.get_source_count() == 0:
		return
	var source_id := ts.get_source_id(0)
	var src := ts.get_source(source_id) as TileSetAtlasSource
	if src == null:
		return
	var coords: Array[Vector2i] = []
	var weights: Array[float] = []
	for i in src.get_tiles_count():
		var c := src.get_tile_id(i)
		var td := src.get_tile_data(c, 0)
		if td != null and td.probability > 0.0:
			coords.append(c)
			weights.append(td.probability)
	if coords.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC0FFEE   # cosmetic only — any fixed seed
	for y in range(-FLOOR_HALF_TILES, FLOOR_HALF_TILES + 1):
		for x in range(-FLOOR_HALF_TILES, FLOOR_HALF_TILES + 1):
			var r := rng.randf() * _sum(weights)
			var pick := 0
			for i in weights.size():
				r -= weights[i]
				if r <= 0.0:
					pick = i
					break
			_floor.set_cell(Vector2i(x, y), source_id, coords[pick])


static func _sum(arr: Array[float]) -> float:
	var s := 0.0
	for v in arr:
		s += v
	return s


# --- Enemy brush ---------------------------------------------------------------------------

func _spawn_brush(at: Vector2) -> void:
	var e: Node2D
	if _brush == DUMMY_ID:
		e = PLACEHOLDER_SCENE.instantiate()
		e.set_script(LabDummy)
		e.max_health = _dummy_hp
		e.defence = _dummy_def
	else:
		var scene := DebugContent.enemy_scene(_brush)
		if scene == null:
			return
		e = scene.instantiate()
	e.global_position = at
	_enemies.add_child(e)
	if _freeze:
		_set_frozen(e, true)


func _despawn_nearest(at: Vector2) -> void:
	var best: Node2D = null
	var best_d := INF
	for e in _enemies.get_children():
		var d: float = e.global_position.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = e
	var max_d := 4.0 * GameConstants.PX_PER_TILE
	if best != null and best_d <= max_d * max_d:
		best.queue_free()


## Freeze = disable the brain (FSM node), not the body — the sprite/hurtbox stay live so
## frozen enemies still take hits, they just stop thinking and moving.
func _set_frozen(e: Node, frozen: bool) -> void:
	var fsm := e.get_node_or_null("FSM")
	if fsm != null:
		fsm.process_mode = Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT
	if frozen and e is CharacterBody2D:
		e.velocity = Vector2.ZERO


func _kill_all(real_death: bool) -> void:
	for e in _enemies.get_children():
		if real_death and e.has_method("die"):
			e.die()
		else:
			e.queue_free()


# --- Cheats ----------------------------------------------------------------------------------

func _apply_god() -> void:
	_player.grant_spawn_grace(1e9 if _god else 0.0)


func _apply_cheat_stats(skill: int, speed: int, defence: int) -> void:
	_cheat_buff.skill_modifier = skill
	_cheat_buff.speed_modifier = speed
	_cheat_buff.defence_modifier = defence
	# add_buff is idempotent for an already-registered buff and recomputes stats either way.
	_player.add_buff(_cheat_buff)


# --- Panel -----------------------------------------------------------------------------------

func _set_panel_open(open: bool) -> void:
	_panel.visible = open
	_hint.visible = not open
	get_tree().paused = open


func _build_ui() -> void:
	var theme := _make_theme()

	_hint = Label.new()
	_hint.theme = theme
	_hint.text = "Tab: lab panel   F3: dmg   `: console"
	_hint.position = Vector2(90, 2)
	_lab_ui.add_child(_hint)

	_panel = PanelContainer.new()
	_panel.theme = theme
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_W
	_lab_ui.add_child(_panel)

	_tabs = TabContainer.new()
	_tabs.tab_changed.connect(func(_i): _save_state())
	_panel.add_child(_tabs)

	_build_cheats_tab(_tab_page("cheats"))
	_build_enemies_tab(_tab_page("enemies"))
	_build_item_palette(_tab_page("items"))
	_highlight_brush()

	_tabs.current_tab = clampi(DebugState.get_value("combat_lab", "tab", 0), 0, 2)


## Add one scrolling tab page to the TabContainer; its node name is the tab label.
func _tab_page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func _build_cheats_tab(box: VBoxContainer) -> void:
	_check(box, "god mode", _god, func(on):
		_god = on
		_apply_god()
		_save_state())
	var stats := GridContainer.new()
	stats.columns = 2
	box.add_child(stats)
	_grid_spin(stats, "+skill", _cheat_buff.skill_modifier, -50, 200, func(v):
		_apply_cheat_stats(v, _cheat_buff.speed_modifier, _cheat_buff.defence_modifier)
		_save_state())
	_grid_spin(stats, "+speed", _cheat_buff.speed_modifier, -50, 200, func(v):
		_apply_cheat_stats(_cheat_buff.skill_modifier, v, _cheat_buff.defence_modifier)
		_save_state())
	_grid_spin(stats, "+def", _cheat_buff.defence_modifier, -50, 200, func(v):
		_apply_cheat_stats(_cheat_buff.skill_modifier, _cheat_buff.speed_modifier, v)
		_save_state())
	_button(box, "heal", func():
		_player.health = _player.max_health
		GlobalEvent.player_health_changed.emit(_player.health))
	_button(box, "reload item .tres", func():
		DebugContent.reload_slotted_items())


func _build_enemies_tab(box: VBoxContainer) -> void:
	_header(box, "LMB place, RMB remove")
	_check(box, "freeze AI", _freeze, func(on):
		_freeze = on
		for e in _enemies.get_children():
			_set_frozen(e, on)
		_save_state())
	_button(box, "kill all (drops+bestiary)", func(): _kill_all(true))
	_button(box, "clear enemies", func(): _kill_all(false))
	_button(box, "clear pickups", func():
		for p in _pickups.get_children():
			p.queue_free())

	var dummy_grid := GridContainer.new()
	dummy_grid.columns = 2
	box.add_child(dummy_grid)
	_grid_spin(dummy_grid, "dummy hp", _dummy_hp, 0, 9999, func(v):
		_dummy_hp = v
		_save_state())
	_grid_spin(dummy_grid, "dummy def", _dummy_def, 0, 99, func(v):
		_dummy_def = v
		_save_state())

	_build_brush_list(box)


func _build_brush_list(box: VBoxContainer) -> void:
	_header(box, "brush")
	var ids: Array[StringName] = [DUMMY_ID]
	for eid in DebugContent.scan_enemy_ids():
		if eid != &"placeholder":
			ids.append(eid)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for eid in ids:
		var b := Button.new()
		b.text = String(eid)
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			_brush = eid
			_highlight_brush()
			_save_state())
		grid.add_child(b)
		_brush_buttons[eid] = b


func _highlight_brush() -> void:
	for eid in _brush_buttons:
		_brush_buttons[eid].modulate = Color(1.0, 0.9, 0.3) if eid == _brush else Color.WHITE


## Icon grids per category. LMB equips (weapon/hat/robe slot, spells to the first free spell
## slot, else bag); RMB drops the item as a real ground pickup, exercising the pickup flow.
func _build_item_palette(box: VBoxContainer) -> void:
	var items := DebugContent.scan_items()
	for cat in items:
		_header(box, "%s — LMB equip, RMB drop" % cat)
		var grid := GridContainer.new()
		grid.columns = 6
		box.add_child(grid)
		for entry in items[cat]:
			var item: ItemResource = entry["item"]
			var b := TextureButton.new()
			b.texture_normal = item.icon
			b.ignore_texture_size = true
			b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			b.custom_minimum_size = Vector2(16, 16)
			b.tooltip_text = entry["name"]
			b.pressed.connect(_equip_item.bind(item))
			b.gui_input.connect(func(ev: InputEvent):
				var mb := ev as InputEventMouseButton
				if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
					GlobalEvent.loot_dropped.emit(item, _player.global_position \
							+ Vector2(2 * GameConstants.PX_PER_TILE, 0)))
			grid.add_child(b)


func _equip_item(item: ItemResource) -> void:
	if item.get_item_type() == GlobalInventory.ItemType.SPELL:
		var idx := GlobalInventory.spell_slots.first_empty()
		if idx >= 0:
			GlobalInventory.spell_slots.add_at(idx, item)
			return
	GlobalInventory.bag_slots.add_at_first_empty(item)


# --- Theme (game theme + compact chrome so controls match the 8px HUD) ----------------------

## The game theme.tres styles only Label/PanelContainer; Button/CheckBox/SpinBox/TabContainer
## fall back to Godot's default styleboxes, which are sized for a 16px UI and dwarf the pixel
## font. Duplicate the game theme and pin tight, HUD-consistent chrome onto those types.
func _make_theme() -> Theme:
	var t: Theme = (load("res://gui/theme.tres") as Theme).duplicate(true)
	var base := Color(0.16, 0.18, 0.22)
	var lit := Color(0.24, 0.28, 0.35)
	var dark := Color(0.10, 0.11, 0.14)
	var edge := Color(0.38, 0.44, 0.53)

	for state in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(state, "Button", _sb(dark if state == "pressed" else \
				(lit if state == "hover" else base), edge))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	t.set_stylebox("normal", "LineEdit", _sb(dark, edge))
	t.set_stylebox("focus", "LineEdit", _sb(dark, Color(0.6, 0.72, 0.88)))
	t.set_constant("minimum_character_width", "LineEdit", 3)

	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CheckBox", _sb_pad(2))
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())

	t.set_stylebox("tab_selected", "TabContainer", _sb(lit, edge))
	t.set_stylebox("tab_unselected", "TabContainer", _sb(dark, edge))
	t.set_stylebox("tab_hovered", "TabContainer", _sb(base, edge))
	t.set_stylebox("panel", "TabContainer", _sb_pad(2))
	t.set_constant("icon_max_width", "TabContainer", 0)
	return t


## Compact filled box: 1px border, wide-but-short content margins for dense controls.
func _sb(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.content_margin_left = 3
	s.content_margin_right = 3
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	return s


func _sb_pad(px: int) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = px
	s.content_margin_right = px
	s.content_margin_top = px
	s.content_margin_bottom = px
	return s


# --- Small control builders (theme font is 8px — keep everything dense) ---------------------

func _header(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.7, 0.85, 1.0)
	parent.add_child(l)


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _check(parent: Control, text: String, value: bool, cb: Callable) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.toggled.connect(cb)
	parent.add_child(c)


func _grid_spin(grid: GridContainer, text: String, value: int, lo: int, hi: int,
		cb: Callable) -> void:
	var l := Label.new()
	l.text = text
	grid.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.value = clampi(value, lo, hi)
	sb.value_changed.connect(func(v): cb.call(int(v)))
	grid.add_child(sb)


# --- Persistence ------------------------------------------------------------------------------

func _restore_state() -> void:
	_god = DebugState.get_value("combat_lab", "god", false)
	_freeze = DebugState.get_value("combat_lab", "freeze", false)
	_dummy_hp = DebugState.get_value("combat_lab", "dummy_hp", 0)
	_dummy_def = DebugState.get_value("combat_lab", "dummy_def", 0)
	_brush = StringName(DebugState.get_value("combat_lab", "brush", String(DUMMY_ID)))
	var sk: int = DebugState.get_value("combat_lab", "cheat_skill", 0)
	var sp: int = DebugState.get_value("combat_lab", "cheat_speed", 0)
	var df: int = DebugState.get_value("combat_lab", "cheat_def", 0)
	if sk != 0 or sp != 0 or df != 0:
		_apply_cheat_stats(sk, sp, df)


func _save_state() -> void:
	DebugState.set_value("combat_lab", "god", _god)
	DebugState.set_value("combat_lab", "freeze", _freeze)
	DebugState.set_value("combat_lab", "dummy_hp", _dummy_hp)
	DebugState.set_value("combat_lab", "dummy_def", _dummy_def)
	DebugState.set_value("combat_lab", "brush", String(_brush))
	DebugState.set_value("combat_lab", "cheat_skill", _cheat_buff.skill_modifier)
	DebugState.set_value("combat_lab", "cheat_speed", _cheat_buff.speed_modifier)
	DebugState.set_value("combat_lab", "cheat_def", _cheat_buff.defence_modifier)
	if _tabs != null:
		DebugState.set_value("combat_lab", "tab", _tabs.current_tab)
