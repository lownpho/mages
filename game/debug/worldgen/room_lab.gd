extends Node2D
## Room Lab — a live room-tuning tool. Pick a room type / biome / generator from dropdowns
## populated by scanning the content folders, tweak every dial — the organic wall shape,
## blob footprint, and the selected generator's @exports, introspected — and see a whole
## grid of rooms rebuild instantly. Rooms are synthesized RoomSpecs (not pulled from a real
## world graph), each cell seeded distinctly so one parameter set shows its variety at a
## glance. NOTE: cells in grid row/column 0 sit on the synthetic world edge, so their
## north/west walls stay sealed and un-eroded — that's the real edge-of-world behaviour.
##
## The lab closes the loop back to the content: dials that differ from their authored
## value highlight yellow (each row's `<` button reverts it), and **Write back** saves the
## changed dials into the authored .tres files (gen_config / biome / room type) after a
## confirmation diff — no more hand-transcribing numbers into the inspector.
##
## Keys: R reroll seed · P protected overlay · M reachability overlay · T real-tileset
## presentation preview · C copy the pinned/first room as ASCII to the clipboard ·
## click a cell to pin/enlarge it (Esc unpins). Selections persist across runs; CLI
## deep-links: `-- seed=123 type=glade_arena biome=glade`.

const SHARED_ROOMS_DIR := "res://world_content/rooms"
const BIOMES_DIR := "res://world_content/biomes"
const GENERATORS_DIR := "res://worldgen/generators"
const PANEL_W := 320.0
const FROM_ROOM_TYPE := "(from room type)"
const NO_GENERATOR := "(none — empty room)"
const DIRTY := Color(1.0, 0.9, 0.3)

@export var config: GenConfig

@onready var _view: Node2D = $RoomsView
var _param_box: VBoxContainer

var _room_type_ids: Array[StringName] = []
var _biome_ids: Array[StringName] = []
var _generator_paths: Array[String] = []   ## script paths, parallel to the override dropdown (minus the two sentinels)

# Live state edited by the controls.
var _base_seed: int = 0
var _type_id: StringName = &""
var _biome_id: StringName = &""
var _cols := 3
var _rows := 3
var _size := Vector2i.ONE
var _slot_tiles := 32
var _door_width := 3
var _decor_density := 0.05
var _min_reach := 0.20
var _wall_depth := 5
var _wall_erode := 0
var _wall_period := 10
var _corner_radius := 6
var _wall_inset := 4
var _blob := false
var _sides := {WorldSpec.SIDE_NORTH: true, WorldSpec.SIDE_EAST: true,
		WorldSpec.SIDE_SOUTH: true, WorldSpec.SIDE_WEST: true}
var _open_passages := false      ## doors vs fully-open sides
var _generator: RoomGenBase = null   ## the live-edited generator instance (may be null)

var _gen_dd: OptionButton
var _blob_cb: CheckBox
var _seed_label: Label
var _seed_edit: LineEdit
var _regen_queued := false
var _pinned := -1                ## grid index enlarged to a single cell; -1 = full grid
var _pres_mode := false          ## render with the biome's real tilesets instead of class colors
var _outputs: Array = []         ## last generated RoomOutputs (full grid, even when pinned)
var _last_cfg: GenConfig = null  ## the override config the current _outputs were built with

## Dial registry for dirty-highlighting, per-dial revert, and write-back.
## key -> {authored: Variant, current: Callable() -> Variant, revert: Callable, lbl: Label}
var _dials: Dictionary = {}


func _ready() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_view.panel_width = PANEL_W
	_scan_content()
	_slot_tiles = config.room_slot_tiles
	_door_width = config.door_width_tiles
	_min_reach = config.min_reachable_floor_ratio
	_wall_depth = config.wall_extra_depth
	_wall_erode = config.wall_outer_erode
	_wall_period = config.wall_noise_period
	_corner_radius = config.corner_radius
	_wall_inset = config.wall_inset_max
	_restore_state()
	var b0 := config.biome_by_id(_biome_id)
	if b0 != null:
		_decor_density = b0.decor_density
	var rt0 := config.room_type_by_id(_type_id)
	if rt0 != null:
		_blob = rt0.footprint_blob
	_build_ui()
	_sync_generator_from_selection()
	_view.set_presentation(_pres_mode)
	_regenerate()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_R:
			_base_seed = randi()
			_save_state()
			_regenerate()
		KEY_P:
			_view.toggle_protected()
		KEY_M:
			_view.toggle_reach()
		KEY_T:
			_set_pres_mode(not _pres_mode)
		KEY_C:
			_copy_ascii()
		KEY_ESCAPE:
			if _pinned >= 0:
				_pinned = -1
				_push_view()


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell: int = _view.cell_at_screen_pos(mb.position)
	if cell < 0:
		return
	if _pinned >= 0:
		_pinned = -1
	else:
		_pinned = cell
	_push_view()


# --- Content scan ------------------------------------------------------------------------

func _scan_content() -> void:
	# Room types: the shared folder plus each biome's rooms/ subfolder.
	var room_dirs: Array[String] = [SHARED_ROOMS_DIR]
	for sub in _list_subdirs(BIOMES_DIR):
		room_dirs.append("%s/%s/rooms" % [BIOMES_DIR, sub])
	for dir in room_dirs:
		for f in _list_dir(dir, ".tres"):
			var res := load(dir + "/" + f)
			var rt := res as RoomTypeDef
			if rt != null and rt.id != &"":
				_room_type_ids.append(rt.id)
	# Biomes live in per-biome subfolders as <id>/<id>.tres.
	for sub in _list_subdirs(BIOMES_DIR):
		var path := "%s/%s/%s.tres" % [BIOMES_DIR, sub, sub]
		if ResourceLoader.exists(path):
			var b: BiomeDef = load(path)
			if b != null and b.id != &"":
				_biome_ids.append(b.id)
	for f in _list_dir(GENERATORS_DIR, ".gd"):
		if f == "generator_base.gd":
			continue
		_generator_paths.append(GENERATORS_DIR + "/" + f)
	_type_id = _room_type_ids[0] if not _room_type_ids.is_empty() else &""
	_biome_id = config.starting_biome if config.starting_biome in _biome_ids \
			else (_biome_ids[0] if not _biome_ids.is_empty() else &"")


func _list_dir(dir_path: String, suffix: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		# Editor writes .import/.uid siblings; match only the real resource/script files.
		if f.ends_with(suffix):
			out.append(f)
	out.sort()
	return out


func _list_subdirs(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for sub in d.get_directories():
		out.append(sub)
	out.sort()
	return out


# --- Persistence / deep links --------------------------------------------------------------

func _restore_state() -> void:
	_base_seed = DebugState.get_value("room_lab", "seed", randi())
	_cols = DebugState.get_value("room_lab", "cols", _cols)
	_rows = DebugState.get_value("room_lab", "rows", _rows)
	_pres_mode = DebugState.get_value("room_lab", "presentation", false)
	var t := StringName(DebugState.get_value("room_lab", "type", String(_type_id)))
	if t in _room_type_ids:
		_type_id = t
	var b := StringName(DebugState.get_value("room_lab", "biome", String(_biome_id)))
	if b in _biome_ids:
		_biome_id = b
	# CLI overrides win over stored state.
	_base_seed = DebugState.cli_int("seed", _base_seed)
	var cli_t := StringName(DebugState.cli_arg("type"))
	if cli_t in _room_type_ids:
		_type_id = cli_t
	var cli_b := StringName(DebugState.cli_arg("biome"))
	if cli_b in _biome_ids:
		_biome_id = cli_b


func _save_state() -> void:
	DebugState.set_value("room_lab", "seed", _base_seed)
	DebugState.set_value("room_lab", "cols", _cols)
	DebugState.set_value("room_lab", "rows", _rows)
	DebugState.set_value("room_lab", "presentation", _pres_mode)
	DebugState.set_value("room_lab", "type", String(_type_id))
	DebugState.set_value("room_lab", "biome", String(_biome_id))


# --- UI construction ---------------------------------------------------------------------

func _build_ui() -> void:
	var vbox: VBoxContainer = $UI/Panel/Scroll/VBox

	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "seed + Enter"
	_seed_edit.text_submitted.connect(func(text: String):
		_base_seed = text.to_int()
		_seed_edit.release_focus()
		_save_state()
		_regenerate())
	vbox.add_child(_labeled("Seed (R rerolls)", _seed_edit))

	_add_dropdown(vbox, "Room type", _room_type_ids.map(func(s): return String(s)),
			_room_type_ids.find(_type_id), _on_type_changed)
	_add_dropdown(vbox, "Biome", _biome_ids.map(func(s): return String(s)),
			_biome_ids.find(_biome_id), _on_biome_changed)

	var gen_names: Array = [FROM_ROOM_TYPE, NO_GENERATOR]
	for p in _generator_paths:
		gen_names.append(p.get_file().trim_suffix(".gd"))
	_gen_dd = _add_dropdown(vbox, "Generator", gen_names, 0, _on_generator_changed)

	_add_int(vbox, "Grid columns", _cols, 1, 6, func(v):
		_cols = v
		_save_state())
	_add_int(vbox, "Grid rows", _rows, 1, 6, func(v):
		_rows = v
		_save_state())
	_add_int(vbox, "Size slots W", _size.x, 1, 3, func(v): _size.x = v)
	_add_int(vbox, "Size slots H", _size.y, 1, 3, func(v): _size.y = v)
	_add_int(vbox, "Slot tiles", _slot_tiles, 8, 96, func(v): _slot_tiles = v, "cfg:room_slot_tiles")
	_add_int(vbox, "Door width", _door_width, 1, 9, func(v): _door_width = v, "cfg:door_width_tiles")
	_add_float(vbox, "Decor density", _decor_density, 0.0, 0.4, 0.005,
			func(v): _decor_density = v, "biome:decor_density")
	_add_float(vbox, "Min reach ratio", _min_reach, 0.0, 1.0, 0.01,
			func(v): _min_reach = v, "cfg:min_reachable_floor_ratio")

	var wall_hdr := Label.new()
	wall_hdr.text = "— Wall shape —"
	vbox.add_child(wall_hdr)
	_add_int(vbox, "Band depth (noise)", _wall_depth, 0, 12, func(v): _wall_depth = v,
			"cfg:wall_extra_depth")
	_add_int(vbox, "Side inset max", _wall_inset, 0, 12, func(v): _wall_inset = v,
			"cfg:wall_inset_max")
	_add_int(vbox, "Outer erode", _wall_erode, 0, 8, func(v): _wall_erode = v,
			"cfg:wall_outer_erode")
	_add_int(vbox, "Noise period", _wall_period, 2, 32, func(v): _wall_period = v,
			"cfg:wall_noise_period")
	_add_int(vbox, "Corner radius", _corner_radius, 0, 16, func(v): _corner_radius = v,
			"cfg:corner_radius")
	_blob_cb = _add_checkbox(vbox, "Blob footprint", _blob, func(v): _blob = v,
			"rt:footprint_blob")

	_add_checkbox(vbox, "Open sides (not doors)", _open_passages, func(v): _open_passages = v)
	var pres_cb := CheckBox.new()
	pres_cb.text = "Real tilesets (T)"
	pres_cb.button_pressed = _pres_mode
	pres_cb.toggled.connect(_set_pres_mode)
	vbox.add_child(pres_cb)
	var sides_row := HBoxContainer.new()
	sides_row.add_child(_side_check("N", WorldSpec.SIDE_NORTH))
	sides_row.add_child(_side_check("E", WorldSpec.SIDE_EAST))
	sides_row.add_child(_side_check("S", WorldSpec.SIDE_SOUTH))
	sides_row.add_child(_side_check("W", WorldSpec.SIDE_WEST))
	vbox.add_child(_labeled("Passage sides", sides_row))

	var btns := HBoxContainer.new()
	var reroll := Button.new()
	reroll.text = "Reroll (R)"
	reroll.pressed.connect(func():
		_base_seed = randi()
		_save_state()
		_regenerate())
	btns.add_child(reroll)
	var ascii := Button.new()
	ascii.text = "ASCII (C)"
	ascii.pressed.connect(_copy_ascii)
	btns.add_child(ascii)
	var wb := Button.new()
	wb.text = "Write back"
	wb.pressed.connect(_confirm_writeback)
	btns.add_child(wb)
	vbox.add_child(btns)
	_seed_label = Label.new()
	_seed_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_seed_label)

	var hdr := Label.new()
	hdr.text = "— Generator params —"
	vbox.add_child(hdr)
	_param_box = VBoxContainer.new()
	vbox.add_child(_param_box)


func _side_check(text: String, side: int) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = _sides[side]
	cb.toggled.connect(func(on):
		_sides[side] = on
		_schedule_regen())
	return cb


func _rebuild_param_panel() -> void:
	# Drop stale generator dial registrations along with their rows.
	for key in _dials.keys():
		if String(key).begins_with("gen:"):
			_dials.erase(key)
	for c in _param_box.get_children():
		c.queue_free()
	if _generator == null:
		var none := Label.new()
		none.text = "(no generator)"
		_param_box.add_child(none)
		return
	for prop in _generator.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var pname: String = prop.name
		if pname.begins_with("_"):
			continue
		var value: Variant = _generator.get(pname)
		var dial_key := "gen:" + pname
		match prop.type:
			TYPE_INT:
				var lo := 0
				var hi := 64
				if prop.hint == PROPERTY_HINT_RANGE:
					var rparts: PackedStringArray = prop.hint_string.split(",")
					lo = int(rparts[0])
					hi = int(rparts[1])
				_add_int(_param_box, pname, value, lo, maxi(hi, value), _gen_setter(pname), dial_key)
			TYPE_FLOAT:
				var flo := 0.0
				var fhi := 1.0
				var step := 0.01
				if prop.hint == PROPERTY_HINT_RANGE:
					var fparts: PackedStringArray = prop.hint_string.split(",")
					flo = float(fparts[0])
					fhi = float(fparts[1])
					if fparts.size() > 2:
						step = float(fparts[2])
				_add_float(_param_box, pname, value, flo, fhi, step, _gen_setter(pname), dial_key)
			TYPE_BOOL:
				_add_checkbox(_param_box, pname, value, _gen_setter(pname), dial_key)


func _gen_setter(prop: String) -> Callable:
	return func(v):
		_generator.set(prop, v)
		_schedule_regen()


# --- Generic control helpers -------------------------------------------------------------
# Rows built by _add_int/_add_float/_add_checkbox can register as a *dial* (dial_key != ""):
# the label tints yellow while the value differs from the authored one, the `<` button
# reverts it, and _confirm_writeback offers to save the change into the authored .tres.

func _labeled(text: String, control: Control) -> Control:
	var row := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)
	row.add_child(control)
	return row


## Register a dial row: remembers the authored value, wires the revert button, and
## returns the tint-refresh callable the control's change handler should invoke.
func _register_dial(dial_key: String, value: Variant, lbl: Label, revert_btn: Button,
		current: Callable, set_control: Callable) -> Callable:
	_dials[dial_key] = {"authored": value, "current": current, "lbl": lbl}
	var refresh := func():
		var dirty: bool = _dials[dial_key]["current"].call() != _dials[dial_key]["authored"]
		lbl.modulate = DIRTY if dirty else Color.WHITE
		revert_btn.visible = dirty
	revert_btn.pressed.connect(func():
		set_control.call(_dials[dial_key]["authored"])
		refresh.call())
	revert_btn.visible = false
	return refresh


func _dial_row(parent: VBoxContainer, text: String, control: Control,
		dial_key: String, value: Variant, current: Callable, set_control: Callable) -> Callable:
	var row := VBoxContainer.new()
	var top := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lbl)
	var refresh := Callable()
	if dial_key != "":
		var revert := Button.new()
		revert.text = "<"
		revert.tooltip_text = "revert to authored value"
		top.add_child(revert)
		refresh = _register_dial(dial_key, value, lbl, revert, current, set_control)
	row.add_child(top)
	row.add_child(control)
	parent.add_child(row)
	return refresh


func _add_dropdown(parent: VBoxContainer, text: String, items: Array, selected: int,
		cb: Callable) -> OptionButton:
	var dd := OptionButton.new()
	for it in items:
		dd.add_item(String(it))
	if selected >= 0:
		dd.selected = selected
	dd.item_selected.connect(cb)
	parent.add_child(_labeled(text, dd))
	return dd


func _add_int(parent: VBoxContainer, text: String, value: int, lo: int, hi: int,
		cb: Callable, dial_key := "") -> void:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = 1
	sb.value = clampi(value, lo, hi)
	var refresh := _dial_row(parent, text, sb, dial_key, clampi(value, lo, hi),
			func(): return int(sb.value), func(v): sb.value = v)
	sb.value_changed.connect(func(v):
		cb.call(int(v))
		if refresh.is_valid():
			refresh.call()
		_schedule_regen())


func _add_float(parent: VBoxContainer, text: String, value: float, lo: float, hi: float,
		step: float, cb: Callable, dial_key := "") -> void:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = clampf(value, lo, hi)
	var refresh := _dial_row(parent, text, sb, dial_key, clampf(value, lo, hi),
			func(): return float(sb.value), func(v): sb.value = v)
	sb.value_changed.connect(func(v):
		cb.call(float(v))
		if refresh.is_valid():
			refresh.call()
		_schedule_regen())


func _add_checkbox(parent: VBoxContainer, text: String, value: bool, cb: Callable,
		dial_key := "") -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = value
	var refresh := Callable()
	if dial_key != "":
		# button_pressed (not set_pressed_no_signal) so a revert re-fires toggled and the
		# backing lab state actually changes.
		refresh = _dial_row(parent, "", box, dial_key, value,
				func(): return box.button_pressed, func(v): box.button_pressed = v)
	else:
		parent.add_child(box)
	box.toggled.connect(func(on):
		cb.call(on)
		if refresh.is_valid():
			refresh.call()
		_schedule_regen())
	return box


# --- Selection callbacks -----------------------------------------------------------------

func _on_type_changed(idx: int) -> void:
	_type_id = _room_type_ids[idx]
	_gen_dd.selected = 0   # reset override to "from room type"
	var rt := config.room_type_by_id(_type_id)
	_blob = rt != null and rt.footprint_blob
	_blob_cb.set_pressed_no_signal(_blob)
	if _dials.has("rt:footprint_blob"):
		_dials["rt:footprint_blob"]["authored"] = _blob
	_save_state()
	_sync_generator_from_selection()
	_regenerate()


func _on_biome_changed(idx: int) -> void:
	_biome_id = _biome_ids[idx]
	_save_state()
	_regenerate()


func _on_generator_changed(_idx: int) -> void:
	_sync_generator_from_selection()
	_regenerate()


## Resolve the live generator instance from the two dropdowns: index 0 clones the room type's
## authored generator, index 1 is empty, the rest instantiate a generator script fresh (defaults).
func _sync_generator_from_selection() -> void:
	var sel := _gen_dd.selected if _gen_dd != null else 0
	if sel == 0:
		var rt := config.room_type_by_id(_type_id)
		_generator = rt.generator.duplicate(true) if rt != null and rt.generator != null else null
	elif sel == 1:
		_generator = null
	else:
		var script: GDScript = load(_generator_paths[sel - 2])
		_generator = script.new() as RoomGenBase
	_rebuild_param_panel()


# --- Write-back ----------------------------------------------------------------------------

## Config dials the lab can write back: dial key -> GenConfig property.
const CFG_FIELDS := {
	"cfg:room_slot_tiles": "room_slot_tiles",
	"cfg:door_width_tiles": "door_width_tiles",
	"cfg:min_reachable_floor_ratio": "min_reachable_floor_ratio",
	"cfg:wall_extra_depth": "wall_extra_depth",
	"cfg:wall_inset_max": "wall_inset_max",
	"cfg:wall_outer_erode": "wall_outer_erode",
	"cfg:wall_noise_period": "wall_noise_period",
	"cfg:corner_radius": "corner_radius",
}


## Every dirty dial as {key, field, old, new, target} rows. `target` is the authored
## resource the change lands in.
func _pending_changes() -> Array:
	var out: Array = []
	var biome := config.biome_by_id(_biome_id)
	var rt := config.room_type_by_id(_type_id)
	for key in _dials:
		var cur: Variant = _dials[key]["current"].call()
		if cur == _dials[key]["authored"]:
			continue
		var k := String(key)
		if CFG_FIELDS.has(k):
			out.append({"key": k, "field": CFG_FIELDS[k], "old": _dials[key]["authored"],
					"new": cur, "target": config})
		elif k == "biome:decor_density" and biome != null:
			out.append({"key": k, "field": "decor_density", "old": _dials[key]["authored"],
					"new": cur, "target": biome})
		elif k == "rt:footprint_blob" and rt != null:
			out.append({"key": k, "field": "footprint_blob", "old": _dials[key]["authored"],
					"new": cur, "target": rt})
		elif k.begins_with("gen:") and rt != null and _gen_dd.selected == 0:
			# Generator params only write back when editing the room type's own generator.
			out.append({"key": k, "field": k.trim_prefix("gen:"), "old": _dials[key]["authored"],
					"new": cur, "target": rt})
	return out


func _confirm_writeback() -> void:
	var changes := _pending_changes()
	var dlg := ConfirmationDialog.new()
	if changes.is_empty():
		dlg.title = "Write back"
		dlg.dialog_text = "No dials differ from their authored values."
		dlg.get_ok_button().visible = false
	else:
		var lines: Array[String] = []
		for c in changes:
			var res: Resource = c["target"]
			lines.append("%s: %s -> %s   (%s)" % [c["field"], c["old"], c["new"],
					res.resource_path.get_file()])
		lines.append("")
		lines.append("World-affecting dials re-roll existing saved worlds (CONFIG_HASH).")
		dlg.title = "Write %d change(s) into the authored .tres files?" % changes.size()
		dlg.dialog_text = "\n".join(lines)
		dlg.confirmed.connect(func(): _apply_writeback(changes))
	add_child(dlg)
	dlg.popup_centered()
	dlg.visibility_changed.connect(func():
		if not dlg.visible:
			dlg.queue_free())


func _apply_writeback(changes: Array) -> void:
	var to_save: Dictionary = {}
	var rt := config.room_type_by_id(_type_id)
	for c in changes:
		var target: Resource = c["target"]
		if String(c["key"]).begins_with("gen:"):
			# The lab edits a duplicate; write the values onto the authored embedded generator.
			if rt.generator != null:
				rt.generator.set(c["field"], c["new"])
		else:
			target.set(c["field"], c["new"])
		to_save[target.resource_path] = target
		# Adopt the new value as authored so the dial reads clean after saving.
		_dials[c["key"]]["authored"] = c["new"]
		_dials[c["key"]]["lbl"].modulate = Color.WHITE
	for path in to_save:
		var err := ResourceSaver.save(to_save[path], path)
		if err != OK:
			push_error("Room Lab: failed to save %s (error %d)" % [path, err])
	# Refresh dirty tints (revert buttons hide via their own refresh on next interaction).
	print("Room Lab: wrote %d change(s) to %d file(s)" % [changes.size(), to_save.size()])


# --- ASCII dump ------------------------------------------------------------------------------

const ASCII_CLASS := {RoomBuilder.FLOOR: ".", RoomBuilder.WALL: "#",
		RoomBuilder.BLOCKER: "o", RoomBuilder.DECOR_FLOOR: ","}


## Copy the pinned (or first) room to the clipboard as ASCII — the fastest way to eyeball
## interiors in a diff/chat, and the format the worldgen review workflow already uses.
func _copy_ascii() -> void:
	if _outputs.is_empty():
		return
	var idx := _pinned if _pinned >= 0 else 0
	var out: RoomOutput = _outputs[idx]
	if out == null:
		return
	var lines: Array[String] = ["# %s  %s  %dx%d  seed %d  spawns %d" % [out.type_id,
			out.biome_id, out.width, out.height, _base_seed + idx, out.spawns.size()]]
	for y in out.height:
		var row := ""
		for x in out.width:
			row += ASCII_CLASS.get(out.tile_grid[y * out.width + x], "?")
		lines.append(row)
	var text := "\n".join(lines)
	DisplayServer.clipboard_set(text)
	print(text)
	print("Room Lab: ASCII copied to clipboard")


# --- Generation --------------------------------------------------------------------------

func _set_pres_mode(on: bool) -> void:
	_pres_mode = on
	_save_state()
	_view.set_presentation(on)


func _schedule_regen() -> void:
	# Coalesce the storm of value_changed signals a single edit can emit into one rebuild.
	if _regen_queued:
		return
	_regen_queued = true
	_regenerate.call_deferred()


func _regenerate() -> void:
	_regen_queued = false
	# Deep-duplicate so mutating dials / the generator can't touch the authored config, and so
	# CONFIG_HASH starts uncached (duplicate resets it) and reflects these overrides.
	var cfg: GenConfig = config.duplicate(true)
	cfg.room_slot_tiles = _slot_tiles
	cfg.door_width_tiles = _door_width
	cfg.min_reachable_floor_ratio = _min_reach
	cfg.wall_extra_depth = _wall_depth
	cfg.wall_outer_erode = _wall_erode
	cfg.wall_noise_period = _wall_period
	cfg.corner_radius = _corner_radius
	cfg.wall_inset_max = _wall_inset
	# duplicate(true) SHARES external .tres subresources, so the biome/room-type defs are still
	# the authored instances — duplicate the two we edit before mutating, or we corrupt the project.
	for i in cfg.biomes.size():
		if cfg.biomes[i] != null and cfg.biomes[i].id == _biome_id:
			var b: BiomeDef = cfg.biomes[i].duplicate(true)
			b.decor_density = _decor_density
			cfg.biomes[i] = b
	for i in cfg.room_types.size():
		if cfg.room_types[i] != null and cfg.room_types[i].id == _type_id:
			var rt: RoomTypeDef = cfg.room_types[i].duplicate(true)
			rt.generator = _generator   # live-edited generator overrides the authored one
			rt.footprint_blob = _blob
			cfg.room_types[i] = rt

	_outputs = []
	var count := _cols * _rows
	for i in count:
		var spec := _make_spec(i)
		_outputs.append(RoomBuilder.build(spec, cfg, _base_seed + i))
	_last_cfg = cfg
	_push_view()


## Hand the view the current outputs — the full grid, or just the pinned cell as a 1x1.
func _push_view() -> void:
	if _last_cfg == null:
		return
	if _pinned >= 0 and _pinned < _outputs.size():
		_view.set_data(_last_cfg, [_outputs[_pinned]], [_base_seed + _pinned], 1, 1)
	else:
		_pinned = -1
		var seeds: Array = []
		for i in _outputs.size():
			seeds.append(_base_seed + i)
		_view.set_data(_last_cfg, _outputs, seeds, _cols, _rows)
	if _seed_label != null:
		_seed_label.text = "seed: %d%s" % [_base_seed,
				"   (pinned cell %d — Esc)" % _pinned if _pinned >= 0 else ""]


## Synthesize a standalone RoomSpec: one type/biome/size with a passage on each enabled side,
## centered. Each grid cell gets a distinct origin_slot so the same params yield varied rooms.
func _make_spec(index: int) -> RoomSpec:
	var spec := RoomSpec.new(Vector2i(index % _cols, index / _cols), _size, _biome_id)
	spec.type_id = _type_id
	var kind := RoomSpec.KIND_OPEN if _open_passages else RoomSpec.KIND_DOOR
	for side in _sides:
		if not _sides[side]:
			continue
		var side_len: int = (_size.x if side == WorldSpec.SIDE_NORTH or side == WorldSpec.SIDE_SOUTH
				else _size.y) * _slot_tiles
		var width: int = side_len if _open_passages else _door_width
		var offset: int = 0 if _open_passages else (side_len - _door_width) / 2
		spec.passages.append(RoomSpec.Passage.new(side, kind, offset, width))
	return spec
