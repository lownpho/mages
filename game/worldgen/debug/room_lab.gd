extends Node2D
## Room Lab — a live room-tuning tool. Pick a room type / biome / generator from dropdowns
## populated by scanning the content folders, tweak every dial (generator params are
## introspected from the selected generator's @exports), and see a whole grid of rooms
## rebuild instantly. Rooms are synthesized RoomSpecs (not pulled from a real world graph),
## each cell seeded distinctly so one parameter set shows its variety at a glance.
##
## R rerolls the base seed, P / M toggle the PROTECTED / reachability overlays.

const ROOM_TYPES_DIR := "res://world_content/room_types"
const BIOMES_DIR := "res://world_content/biomes"
const GENERATORS_DIR := "res://worldgen/generators"
const PANEL_W := 320.0
const FROM_ROOM_TYPE := "(from room type)"
const NO_GENERATOR := "(none — empty room)"

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
var _max_retries := 5
var _min_reach := 0.20
var _force_fallback := false
var _sides := {WorldSpec.SIDE_NORTH: true, WorldSpec.SIDE_EAST: true,
		WorldSpec.SIDE_SOUTH: true, WorldSpec.SIDE_WEST: true}
var _open_passages := false      ## doors vs fully-open sides
var _generator: RoomGenBase = null   ## the live-edited generator instance (may be null)

var _gen_dd: OptionButton
var _regen_queued := false


func _ready() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_view.panel_width = PANEL_W
	_scan_content()
	_slot_tiles = config.room_slot_tiles
	_door_width = config.door_width_tiles
	_max_retries = config.max_room_retries
	_min_reach = config.min_reachable_floor_ratio
	_base_seed = randi()
	_build_ui()
	_sync_generator_from_selection()
	_regenerate()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_R:
			_base_seed = randi()
			_regenerate()
		KEY_P:
			_view.toggle_protected()
		KEY_M:
			_view.toggle_reach()


# --- Content scan ------------------------------------------------------------------------

func _scan_content() -> void:
	for f in _list_dir(ROOM_TYPES_DIR, ".tres"):
		var rt: RoomTypeDef = load(ROOM_TYPES_DIR + "/" + f)
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


# --- UI construction ---------------------------------------------------------------------

func _build_ui() -> void:
	var vbox: VBoxContainer = $UI/Panel/Scroll/VBox

	_add_dropdown(vbox, "Room type", _room_type_ids.map(func(s): return String(s)),
			_room_type_ids.find(_type_id), _on_type_changed)
	_add_dropdown(vbox, "Biome", _biome_ids.map(func(s): return String(s)),
			_biome_ids.find(_biome_id), _on_biome_changed)

	var gen_names: Array = [FROM_ROOM_TYPE, NO_GENERATOR]
	for p in _generator_paths:
		gen_names.append(p.get_file().trim_suffix(".gd"))
	_gen_dd = _add_dropdown(vbox, "Generator", gen_names, 0, _on_generator_changed)

	_add_int(vbox, "Grid columns", _cols, 1, 6, func(v): _cols = v)
	_add_int(vbox, "Grid rows", _rows, 1, 6, func(v): _rows = v)
	_add_int(vbox, "Size slots W", _size.x, 1, 2, func(v): _size.x = v)
	_add_int(vbox, "Size slots H", _size.y, 1, 2, func(v): _size.y = v)
	_add_int(vbox, "Slot tiles", _slot_tiles, 8, 96, func(v): _slot_tiles = v)
	_add_int(vbox, "Door width", _door_width, 1, 9, func(v): _door_width = v)
	_add_float(vbox, "Decor density", _decor_density, 0.0, 0.4, 0.005, func(v): _decor_density = v)
	_add_int(vbox, "Max retries", _max_retries, 0, 20, func(v): _max_retries = v)
	_add_float(vbox, "Min reach ratio", _min_reach, 0.0, 1.0, 0.01, func(v): _min_reach = v)

	_add_checkbox(vbox, "Force fallback", _force_fallback, func(v): _force_fallback = v)
	_add_checkbox(vbox, "Open sides (not doors)", _open_passages, func(v): _open_passages = v)
	var sides_row := HBoxContainer.new()
	sides_row.add_child(_side_check("N", WorldSpec.SIDE_NORTH))
	sides_row.add_child(_side_check("E", WorldSpec.SIDE_EAST))
	sides_row.add_child(_side_check("S", WorldSpec.SIDE_SOUTH))
	sides_row.add_child(_side_check("W", WorldSpec.SIDE_WEST))
	vbox.add_child(_labeled("Passage sides", sides_row))

	var reroll := Button.new()
	reroll.text = "Reroll seed (R)"
	reroll.pressed.connect(func():
		_base_seed = randi()
		_regenerate())
	vbox.add_child(reroll)

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
		match prop.type:
			TYPE_INT:
				var lo := 0
				var hi := 64
				if prop.hint == PROPERTY_HINT_RANGE:
					var rparts: PackedStringArray = prop.hint_string.split(",")
					lo = int(rparts[0])
					hi = int(rparts[1])
				_add_int(_param_box, pname, value, lo, maxi(hi, value), _gen_setter(pname))
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
				_add_float(_param_box, pname, value, flo, fhi, step, _gen_setter(pname))
			TYPE_BOOL:
				_add_checkbox(_param_box, pname, value, _gen_setter(pname))


func _gen_setter(prop: String) -> Callable:
	return func(v):
		_generator.set(prop, v)
		_schedule_regen()


# --- Generic control helpers -------------------------------------------------------------

func _labeled(text: String, control: Control) -> Control:
	var row := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)
	row.add_child(control)
	return row


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
		cb: Callable) -> void:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = 1
	sb.value = clampi(value, lo, hi)
	sb.value_changed.connect(func(v):
		cb.call(int(v))
		_schedule_regen())
	parent.add_child(_labeled(text, sb))


func _add_float(parent: VBoxContainer, text: String, value: float, lo: float, hi: float,
		step: float, cb: Callable) -> void:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = clampf(value, lo, hi)
	sb.value_changed.connect(func(v):
		cb.call(float(v))
		_schedule_regen())
	parent.add_child(_labeled(text, sb))


func _add_checkbox(parent: VBoxContainer, text: String, value: bool, cb: Callable) -> void:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = value
	box.toggled.connect(func(on):
		cb.call(on)
		_schedule_regen())
	parent.add_child(box)


# --- Selection callbacks -----------------------------------------------------------------

func _on_type_changed(idx: int) -> void:
	_type_id = _room_type_ids[idx]
	_gen_dd.selected = 0   # reset override to "from room type"
	_sync_generator_from_selection()
	_regenerate()


func _on_biome_changed(idx: int) -> void:
	_biome_id = _biome_ids[idx]
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


# --- Generation --------------------------------------------------------------------------

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
	cfg.max_room_retries = _max_retries
	cfg.min_reachable_floor_ratio = _min_reach
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
			cfg.room_types[i] = rt

	var outputs: Array = []
	var count := _cols * _rows
	for i in count:
		var spec := _make_spec(i)
		outputs.append(RoomBuilder.build(spec, cfg, _base_seed + i, _force_fallback))
	_view.set_data(cfg, outputs, _cols, _rows)


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
