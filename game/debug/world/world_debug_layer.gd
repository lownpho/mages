class_name WorldDebugLayer
extends Node
## The finite World's in-game debug layer. It is instantiated by the development World only in a
## debug build; the Web preset excludes debug/* and the dev scene holds no resource dependency on
## this file. Tab pauses the actual World and opens compact game-pixel controls.

const SECTION := "world_debug"
const OVERLAY_DEFAULTS := {
	"ideal_path": true, "roles": true, "passages": false, "zones": false,
	"challenge": false, "macro_grid": false, "discovery": false, "outlines": true,
}

var host: Node2D
var tuner := WorldTuner.new()
var overlays := OVERLAY_DEFAULTS.duplicate()
var selected_biome := &""
var panel_open := false

var _canvas: CanvasLayer
var _panel: PanelContainer
var _tabs: TabContainer
var _world_page: Control
var _map: WorldDebugMap
var _combat: WorldDebugCombat
var _world_overlay: WorldDebugOverlay
var _biome_picker: OptionButton
var _knob_box: VBoxContainer
var _totals: Label
var _status: Label
var _location: Label
var _controls: Dictionary[String, SpinBox] = {}
var _labels: Dictionary[String, Label] = {}
var _was_paused := false
var _map_fitted := false


func configure(world_host: Node2D, restore_loadout := true) -> void:
	host = world_host
	process_mode = Node.PROCESS_MODE_ALWAYS
	tuner.setup(host._content, host.world_seed, host._graph.plan, host._graph)
	tuner.timings = host._build_timings.duplicate()
	_restore_state()
	_build_ui()
	_world_overlay = WorldDebugOverlay.new()
	_world_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_world_overlay.z_index = 800
	_world_overlay.visible = false
	host.add_child(_world_overlay)
	_refresh_graph(true)
	if GlobalMap.active != null:
		set_entered_rooms(GlobalMap.active.entered_rooms)
	GlobalMap.discovery_changed.connect(set_entered_rooms)
	_set_fly(bool(DebugState.get_value(SECTION, "fly", false)))
	if restore_loadout:
		_restore_loadout()
	GlobalEvent.slot_updated.connect(_on_slot_updated)


func _exit_tree() -> void:
	if panel_open and get_tree() != null:
		get_tree().paused = _was_paused
	_save_state()


func _process(_delta: float) -> void:
	if host == null or host._player == null or tuner.graph == null:
		return
	var tile := Vector2i((host._player.global_position / GameConstants.PX_PER_TILE).floor())
	var room: GeneratedRoom = host._streamer.interiors.owner_at(tile)
	if room == null:
		_location.text = "tile %d,%d · outside the World" % [tile.x, tile.y]
	else:
		_location.text = "%s/%s · %s · C%d · tile %d,%d" % [room.plan.biome, room.plan.zone,
				room.role_name(), room.plan.challenge, tile.x, tile.y]
	if not panel_open and selected_biome == &"" and room != null:
		select_biome(room.plan.biome)


## _input, not _unhandled_input: focused controls use Tab for focus navigation otherwise.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_TAB:
		set_panel_open(not panel_open)
		get_viewport().set_input_as_handled()
		return
	# Closed, the panel leaves every click to the player, who casts with them.
	var click := event as InputEventMouseButton
	if not panel_open or click == null or not click.pressed:
		return
	# The Map consumes its own clicks. The rest of the panel leaves the right-hand World visible;
	# clicking that area while paused places the Combat tab's selected enemy, or teleports without
	# one. On the Combat tab the right button removes the nearest enemy.
	if _tabs.current_tab == 3 or click.position.x <= _panel.size.x:
		return
	var world_point := get_viewport().get_canvas_transform().affine_inverse() * click.position
	var on_combat := _tabs.current_tab == 2
	if click.button_index == MOUSE_BUTTON_LEFT and on_combat and _combat.selected_enemy != &"":
		_combat.place_selected(world_point)
	elif click.button_index == MOUSE_BUTTON_LEFT:
		host._teleport_to_tile(Vector2i((world_point / GameConstants.PX_PER_TILE).floor()))
	elif click.button_index == MOUSE_BUTTON_RIGHT and on_combat:
		_combat.remove_nearest(world_point)
	else:
		return
	get_viewport().set_input_as_handled()


func set_panel_open(open: bool) -> void:
	if panel_open == open:
		return
	panel_open = open
	_panel.visible = open
	_world_overlay.visible = open
	if open:
		_was_paused = get_tree().paused
		get_tree().paused = true
		_default_to_current_biome()
	else:
		get_tree().paused = _was_paused
	_save_state()


func select_biome(biome_id: StringName) -> void:
	if not tuner.content.biomes.has(biome_id):
		return
	selected_biome = biome_id
	_biome_picker.selected = tuner.content.biome_ids().find(biome_id)
	_build_knob_rows()
	DebugState.set_value(SECTION, "biome", String(selected_biome))


func _default_to_current_biome() -> void:
	if selected_biome != &"" or host._player == null:
		return
	var tile := Vector2i((host._player.global_position / GameConstants.PX_PER_TILE).floor())
	var room: GeneratedRoom = host._streamer.interiors.owner_at(tile)
	select_biome(room.plan.biome if room != null else tuner.content.biome_ids()[0])


func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 900
	add_child(_canvas)
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.offset_right = 174
	_panel.offset_bottom = 180
	_panel.theme = DebugUi.theme()
	_canvas.add_child(_panel)
	_tabs = TabContainer.new()
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(_tabs)
	_world_page = _page("World")
	_build_world_page(_world_page)
	_build_overlay_page(_page("Overlays"))
	_combat = WorldDebugCombat.new()
	_page("Combat").add_child(_combat)
	_combat.configure(host)
	var map_page := _page("Map")
	_map = WorldDebugMap.new()
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.teleport_requested.connect(func(tile: Vector2i) -> void: host._teleport_to_tile(tile))
	map_page.add_child(_map)
	_tabs.current_tab = clampi(int(DebugState.get_value(SECTION, "tab", 0)), 0, 3)
	_tabs.tab_changed.connect(_on_tab_changed)
	_on_tab_changed(_tabs.current_tab)


func _page(title: String) -> MarginContainer:
	var page := MarginContainer.new()
	page.name = title
	page.add_theme_constant_override("margin_left", 2)
	page.add_theme_constant_override("margin_right", 2)
	page.add_theme_constant_override("margin_top", 2)
	page.add_theme_constant_override("margin_bottom", 2)
	_tabs.add_child(page)
	return page


func _build_world_page(page: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var seed_row := HBoxContainer.new()
	box.add_child(seed_row)
	var seed_edit := LineEdit.new()
	seed_edit.name = "SeedEdit"
	seed_edit.text = str(tuner.world_seed)
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.text_submitted.connect(func(value: String) -> void:
		if value.is_valid_int():
			_reseed(value.to_int())
		seed_edit.text = str(tuner.world_seed))
	seed_row.add_child(seed_edit)
	_button(seed_row, "Reroll", func() -> void:
		_reseed(randi())
		seed_edit.text = str(tuner.world_seed))
	_biome_picker = OptionButton.new()
	for biome_id in tuner.content.biome_ids():
		_biome_picker.add_item(String(biome_id))
	_biome_picker.item_selected.connect(func(index: int) -> void:
		select_biome(tuner.content.biome_ids()[index]))
	box.add_child(_biome_picker)
	_knob_box = VBoxContainer.new()
	box.add_child(_knob_box)
	_totals = Label.new()
	_totals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_totals)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	_button(actions, "Rebuild", _rebuild)
	_button(actions, "Save", _save_knobs)
	var fly := CheckBox.new()
	fly.text = "Fly"
	fly.button_pressed = host._flying
	fly.toggled.connect(_set_fly)
	actions.add_child(fly)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_location = Label.new()
	_location.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_location)
	_default_to_current_biome()
	if selected_biome == &"":
		select_biome(tuner.content.biome_ids()[0])


func _build_knob_rows() -> void:
	for child in _knob_box.get_children():
		child.queue_free()
	_controls.clear()
	_labels.clear()
	for knob in WorldTuner.KNOBS:
		_add_value_row(selected_biome, knob, tuner.pending[selected_biome][knob],
				_knob_range(knob), func(value: float) -> void:
				tuner.set_knob(selected_biome, knob, _coerce_knob(knob, value))
				_refresh_controls(), func() -> void:
				tuner.revert_knob(selected_biome, knob)
				_refresh_controls())
	for kind in WorldTuner.RADII:
		_add_value_row(&"", kind, tuner.pending_radii[kind],
				[WorldPlan.RADIUS_MIN, WorldPlan.RADIUS_MAX, 1.0], func(value: float) -> void:
				tuner.set_radius(kind, int(value))
				_refresh_controls(), func() -> void:
				tuner.revert_radius(kind)
				_refresh_controls(), true)
	_refresh_controls()


func _add_value_row(biome_id: StringName, key: StringName, value: Variant, limits: Array,
		changed: Callable, reverted: Callable, radius := false) -> void:
	var row := HBoxContainer.new()
	_knob_box.add_child(row)
	var label := Label.new()
	label.text = ("radius " if radius else "") + String(key).replace("_", " ")
	label.custom_minimum_size.x = 66
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = limits[0]
	spin.max_value = limits[1]
	spin.step = limits[2]
	spin.value = value
	spin.custom_minimum_size.x = 55
	spin.value_changed.connect(changed)
	row.add_child(spin)
	_button(row, "↶", reverted)
	var id := "radius/%s" % key if radius else "%s/%s" % [biome_id, key]
	_controls[id] = spin
	_labels[id] = label


func _build_overlay_page(page: Control) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(box)
	for key in OVERLAY_DEFAULTS:
		var check := CheckBox.new()
		check.text = String(key).replace("_", " ").capitalize()
		check.button_pressed = overlays[key]
		check.toggled.connect(func(on: bool) -> void:
			set_overlay(key, on))
		box.add_child(check)
	var hint := Label.new()
	hint.text = "World/map share these layers.\nPassages: route white · tree grey · loop yellow · shortcut cyan · set piece orange · attachment pink.\nRoles: test grey · teach blue · breather green · spawn white · boss red · miniboss orange · rare purple.\nMap: wheel zoom · middle/right pan · click teleport"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)


func set_overlay(key: String, on: bool) -> void:
	assert(overlays.has(key))
	overlays[key] = on
	DebugState.set_value(SECTION, "overlay_" + key, on)
	_refresh_graph()


func _refresh_controls() -> void:
	if selected_biome == &"" or _controls.is_empty():
		return
	for knob in WorldTuner.KNOBS:
		var id := "%s/%s" % [selected_biome, knob]
		_set_spin(_controls[id], tuner.pending[selected_biome][knob])
		_labels[id].modulate = Color(1.0, 0.72, 0.25) if tuner.is_pending(selected_biome, knob) else Color.WHITE
	for kind in WorldTuner.RADII:
		var id := "radius/%s" % kind
		_set_spin(_controls[id], tuner.pending_radii[kind])
		_labels[id].modulate = Color(1.0, 0.72, 0.25) if tuner.radius_is_pending(kind) else Color.WHITE
	var total := tuner.biome_totals(selected_biome)
	var zones: Array[String] = []
	for zone in tuner.zone_totals(selected_biome):
		zones.append("%s %d/%d" % [zone.id, zone.route_rooms, zone.rooms])
	_totals.text = "%s: %d Zones · route %d · Rooms %d\n%s\nWorld Rooms %d" % [selected_biome,
			total.zones, total.route_rooms, total.rooms, ", ".join(zones), tuner.content.world_room_count()]
	_status.text = "%s%s" % ["pending changes · " if tuner.has_pending() else "",
			"plan %.1f ms · graphs %.1f ms · spawn %.1f ms · stream %.2f ms" % [tuner.timings.plan_ms,
			tuner.timings.graphs_ms, tuner.timings.get("spawn_ms", 0.0), host._streamer.last_work_usec / 1000.0]]


func _rebuild() -> void:
	var next := tuner.rebuild()
	if next == null:
		_status.text = "Rebuild failed; prior World retained."
		return
	host._apply_debug_graph(next, tuner.last_invalidated_biomes, tuner.last_plan_invalidated, false)
	_refresh_graph()
	_refresh_controls()


func _reseed(seed_value: int) -> void:
	var next := tuner.reseed(seed_value)
	if next == null:
		_status.text = "Seed failed to build; prior World retained."
		return
	GlobalMap.reset()
	GameState.fresh_start = true
	host.world_seed = tuner.world_seed
	host._apply_debug_graph(next, tuner.last_invalidated_biomes, true, true)
	_refresh_graph(true)
	_refresh_controls()


## Rereads the World content from disk and rebuilds the World at its seed, keeping the Run's records
## as keys follow place. Pending and unsaved knob and radius edits are discarded; the console warns
## first. Returns what happened, for the console.
func reload_content() -> String:
	var content := ContentLoader.load_content(host.content_root, true)
	if not content.is_valid():
		return "World content has problems; kept the current World:\n" + content.report()
	var next_plan := WorldPlanner.plan(content, host.world_seed)
	var next_graph := WorldGraph.build(next_plan)
	if next_graph == null:
		return "reloaded content built no World; kept the current one"
	host._content = content
	tuner.setup(content, host.world_seed, next_plan, next_graph)
	if not content_has_biome(selected_biome):
		selected_biome = &""
	var every_biome: Dictionary[StringName, bool] = {}
	for biome_id in content.biome_ids():
		every_biome[biome_id] = true
	host._apply_debug_graph(next_graph, every_biome, true, false)
	_refresh_graph()
	_refresh_controls()
	return "reloaded World content and rebuilt seed %d" % host.world_seed


func _save_knobs() -> void:
	var errors := tuner.save_changed()
	_refresh_controls()
	_status.text = "Saved authored Biome knobs; Rebuild is still pending." \
			if errors.is_empty() and tuner.has_pending() else \
			("Saved authored Biome knobs." if errors.is_empty() else "Save failed: %s" % errors)


func _refresh_graph(reset_map := false) -> void:
	if _world_overlay != null:
		_world_overlay.encounters = host._encounters
		_world_overlay.set_data(tuner.graph, overlays)
	if _map != null:
		_map.encounters = host._encounters
		var should_fit := reset_map or not _map_fitted
		_map.set_data(tuner.graph, overlays, false)
		if should_fit:
			_map.call_deferred("fit_world")
		_map_fitted = true


func set_entered_rooms(entered: Dictionary[String, bool]) -> void:
	if _world_overlay != null:
		_world_overlay.set_entered_rooms(entered)
	if _map != null:
		_map.set_entered_rooms(entered)


func _on_tab_changed(tab: int) -> void:
	# Map gets the whole 320x180 game-pixel viewport; other tabs leave the World clickable.
	_panel.offset_right = 320 if tab == 3 else 174
	DebugState.set_value(SECTION, "tab", tab)
	if tab == 3 and _map != null:
		_map.call_deferred("fit_world")


func _set_fly(on: bool) -> void:
	host._set_flying(on)
	DebugState.set_value(SECTION, "fly", on)


func _restore_state() -> void:
	for key in overlays:
		overlays[key] = bool(DebugState.get_value(SECTION, "overlay_" + key, overlays[key]))
	var stored := StringName(DebugState.get_value(SECTION, "biome", ""))
	selected_biome = stored if content_has_biome(stored) else &""


func content_has_biome(id: StringName) -> bool:
	return tuner.content != null and tuner.content.biomes.has(id)


func _save_state() -> void:
	if _tabs != null:
		DebugState.set_value(SECTION, "tab", _tabs.current_tab)
	DebugState.set_value(SECTION, "biome", String(selected_biome))
	DebugState.set_value(SECTION, "fly", host != null and host._flying)


func _restore_loadout() -> void:
	for index in GlobalInventory.SPELL_SLOTS:
		_restore_slot(GlobalInventory.spell_slots.at(index), "spell_%d" % index)
	for index in GlobalInventory.BAG_SIZE:
		_restore_slot(GlobalInventory.bag_slots.at(index), "bag_%d" % index)


func _restore_slot(slot: GlobalInventory.Slot, key: String) -> void:
	var path := String(DebugState.get_value("combat_lab", key, ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		slot.set_item(load(path))


func _on_slot_updated(_slot: GlobalInventory.Slot) -> void:
	for index in GlobalInventory.SPELL_SLOTS:
		_save_slot(GlobalInventory.spell_slots.at(index), "spell_%d" % index)
	for index in GlobalInventory.BAG_SIZE:
		_save_slot(GlobalInventory.bag_slots.at(index), "bag_%d" % index)


func _save_slot(slot: GlobalInventory.Slot, key: String) -> void:
	DebugState.set_value("combat_lab", key, slot.item.resource_path if slot.item != null else "")


func _knob_range(knob: StringName) -> Array:
	for property in (BiomeResource as Script).get_script_property_list():
		if property.name == knob:
			var parts := String(property.hint_string).split(",")
			return [parts[0].to_float(), parts[1].to_float(), parts[2].to_float()]
	return [0.0, 1.0, 0.1]


func _coerce_knob(knob: StringName, value: float) -> Variant:
	return int(value) if knob in [&"room_size", &"passage_width"] else value


func _button(parent: Control, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _set_spin(spin: SpinBox, value: Variant) -> void:
	spin.set_block_signals(true)
	spin.value = value
	spin.set_block_signals(false)
