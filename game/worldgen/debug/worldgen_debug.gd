extends Node2D
## Interactive worldgen debug scene. Grows one view per task:
## 1 = world view, 2 = biome view, 3 = room view, 4 = fly mode over real streamed tiles.
## R rerolls a random seed, Enter in the seed box applies a typed one, 1..4 switch views.
## In the biome view, arrow keys / clicking the corner overview select a biome cell and
## clicking the main grid selects a room; view 3 shows that room (arrows cycle, P/M overlays).

@export var config: GenConfig

@onready var _world_view: Node2D = $WorldView
@onready var _biome_view: Node2D = $BiomeView
@onready var _room_view: Node2D = $RoomView
@onready var _seed_label: Label = $UI/SeedLabel
@onready var _seed_edit: LineEdit = $UI/SeedEdit
@onready var _fly_view: Node2D = $FlyView
@onready var _streamer: WorldStreamer = $FlyView/Streamer
@onready var _flycam: Node2D = $FlyView/FlyCam
@onready var _fly_cam2d: Camera2D = $FlyView/FlyCam/Camera2D
@onready var _overlay_label: Label = $FlyView/Overlay/Label

var world_seed: int = 0
var spec: WorldSpec = null
var current_view: int = 1
var selected_biome := Vector2i.ZERO
var selected_room := 0
var _room_graphs: RoomGraph = null   ## per-session BiomeGraph cache; reset on reseed


func _ready() -> void:
	# The game viewport is 320×180 with canvas_items stretch — unusable for a debug UI.
	# This scene renders in native window pixels instead; views lay out from window size.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_seed_edit.text_submitted.connect(_on_seed_submitted)
	_streamer.config = config
	_streamer.target = _flycam
	_streamer.streaming = false   # only view 4 streams
	world_seed = randi()   # UI-side reroll, not generation code — global RNG is fine here
	_rebuild()
	_switch_view(1)


func _process(_dt: float) -> void:
	if current_view != 4 or _streamer.world_spec == null:
		return
	var chunk_px := config.chunk_tiles * GameConstants.PX_PER_TILE
	var gp := _flycam.global_position
	var cc := Vector2i(floori(gp.x / chunk_px), floori(gp.y / chunk_px))
	_overlay_label.text = "chunk %d,%d   loaded %d\ncache hit %d / miss %d\nassembly %.2f ms" % [
		cc.x, cc.y, _streamer.loaded_chunks(),
		_streamer.cache_hits, _streamer.cache_misses, _streamer.last_assembly_usec / 1000.0]


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_R:
			world_seed = randi()
			_rebuild()
		KEY_1, KEY_2, KEY_3, KEY_4:
			_switch_view(key.keycode - KEY_1 + 1)
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if current_view == 2:
				_move_selection(key.keycode)
			elif current_view == 3:
				_cycle_room(1 if key.keycode == KEY_RIGHT or key.keycode == KEY_DOWN else -1)
		KEY_P:
			if current_view == 3:
				_room_view.toggle_protected()
		KEY_M:
			if current_view == 3:
				_room_view.toggle_reach()


func _unhandled_input(event: InputEvent) -> void:
	if current_view != 2:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell: Vector2i = _biome_view.cell_at_screen_pos(mb.position)
	if cell.x >= 0:
		if cell != selected_biome:
			selected_biome = cell
			selected_room = 0
			_refresh_biome_view()
		return
	var room: int = _biome_view.room_at_screen_pos(mb.position)
	if room >= 0 and room != selected_room:
		selected_room = room
		_refresh_biome_view()


func _move_selection(keycode: int) -> void:
	var d := Vector2i.ZERO
	match keycode:
		KEY_LEFT: d = Vector2i(-1, 0)
		KEY_RIGHT: d = Vector2i(1, 0)
		KEY_UP: d = Vector2i(0, -1)
		KEY_DOWN: d = Vector2i(0, 1)
	var next := selected_biome + d
	if next.x >= 0 and next.y >= 0 and next.x < spec.grid_w and next.y < spec.grid_h:
		selected_biome = next
		selected_room = 0
		_refresh_biome_view()


func _cycle_room(dir: int) -> void:
	var graph := _selected_graph()
	if graph == null:
		return
	selected_room = posmod(selected_room + dir, graph.rooms.size())
	_refresh_room_view()


## Graph of the biome owning the selected cell, or null for an unclaimed (sealed) cell.
func _selected_graph() -> BiomeGraph:
	if spec == null:
		return null
	var bid := spec.biome_at(selected_biome)
	if bid == &"":
		return null
	return _room_graphs.get_biome_graph(spec, bid, config)


func _on_seed_submitted(text: String) -> void:
	world_seed = text.to_int()
	_seed_edit.release_focus()
	_rebuild()


func _rebuild() -> void:
	spec = WorldLayout.build(world_seed, config)
	if spec == null:
		_seed_label.text = "seed %d — LAYOUT FAILED (unsatisfiable adjacency rules?)" % world_seed
		return
	_room_graphs = RoomGraph.new()   # fresh cache — the whole world changed
	selected_biome = Vector2i(clampi(selected_biome.x, 0, spec.grid_w - 1),
			clampi(selected_biome.y, 0, spec.grid_h - 1))
	_seed_label.text = "seed %d   view %d   [R] reroll  [Enter] apply  [1-4] views" % [world_seed, current_view]
	_world_view.set_data(spec, config)
	if current_view == 2:
		_refresh_biome_view()
	elif current_view == 3:
		_refresh_room_view()
	elif current_view == 4:
		_streamer.build_world(world_seed)   # rebuild the streamed world in place


func _refresh_biome_view() -> void:
	if spec == null:
		return
	_biome_view.set_data(spec, config, _selected_graph(), selected_biome, selected_room)


func _refresh_room_view() -> void:
	var graph := _selected_graph()
	if graph == null:
		return
	selected_room = clampi(selected_room, 0, graph.rooms.size() - 1)
	var out := RoomBuilder.build(graph.rooms[selected_room], config, world_seed)
	_room_view.set_data(config, out, selected_room, graph.rooms.size())


# Views live as sibling CanvasItems; only the active one is visible. View 4 is the streamed
# fly world — its camera + streaming only run while it is active (paused otherwise).
func _switch_view(v: int) -> void:
	if v < 1 or v > 4:
		return
	current_view = v
	_world_view.visible = v == 1
	_biome_view.visible = v == 2
	_room_view.visible = v == 3
	_fly_view.visible = v == 4
	_set_fly_active(v == 4)
	if v == 2:
		_refresh_biome_view()
	elif v == 3:
		_refresh_room_view()
	_seed_label.text = "seed %d   view %d   [R] reroll  [Enter] apply  [1-4] views" % [world_seed, current_view]


## Enter/leave fly mode: the fly camera and streaming loop only run in view 4. Loaded chunks are
## kept when leaving (cheap; re-shown on return); a reseed while away still rebuilds on re-entry.
func _set_fly_active(on: bool) -> void:
	if on and (_streamer.world_spec == null or _streamer.world_seed != world_seed):
		_streamer.build_world(world_seed)
	_streamer.streaming = on
	_flycam.set_process(on)
	_fly_cam2d.enabled = on
	if on:
		_fly_cam2d.zoom = Vector2(2, 2)   # 8px tiles visible
