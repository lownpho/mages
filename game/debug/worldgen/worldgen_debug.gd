extends Node2D
## Interactive worldgen debug tool. Four views forming one drill-down chain over the SAME
## world state (selection travels with you):
##
##   1 world  — biome grid + contract ticks; click selects a biome cell
##   2 biome  — the selected biome's room graph; click/arrows select, corner map switches biome
##   3 room   — the selected room's REAL RoomOutput (tiles, PROTECTED [P], reach [M], spawns)
##   4 fly    — free camera over the live streamed world with real enemies
##
## Navigation: Enter drills in (1→2→3→4, landing the camera on the drilled room), Esc backs
## out, T teleports straight to the current selection, 1–4 jump anywhere.
##
## Seeds: R rerolls, typing a seed + Enter applies it, [ / ] walk the session's seed history,
## C copies the seed to the clipboard, B bookmarks it (bookmarks persist in
## user://debug_state.cfg and are listed in the top-right dropdown).
##
## Fly view: O room bounds+tags, G chunk grid, H tier heatmap, V biome borders, and P drops a
## REAL, invulnerable player in at the camera position (P/Esc returns to the camera) — walk
## and fight the actual room; use the ` console to `give`/`equip` gear.
##
## F2 stats sidebar (per-biome room/type/depth counts + build timings), L legend.
## Everything (seed, view, selection, camera, toggles) persists across runs; CLI deep-links:
##   godot --path game res://debug/worldgen/worldgen_debug.tscn -- seed=123 view=4 pos=40,20

@export var config: GenConfig

const PLAYER_SCENE := preload("res://characters/player/player.tscn")

@onready var _world_view: Node2D = $WorldView
@onready var _biome_view: Node2D = $BiomeView
@onready var _room_view: Node2D = $RoomView
@onready var _seed_label: Label = $UI/SeedLabel
@onready var _seed_edit: LineEdit = $UI/SeedEdit
@onready var _fly_view: Node2D = $FlyView
@onready var _streamer: WorldStreamer = $FlyView/Streamer
@onready var _entities: Node2D = $FlyView/Entities
@onready var _flycam: Node2D = $FlyView/FlyCam
@onready var _fly_cam2d: Camera2D = $FlyView/FlyCam/Camera2D
@onready var _fly_hud: CanvasLayer = $FlyView/FlyCam/HUD
@onready var _fly_overlay: CanvasLayer = $FlyView/Overlay
@onready var _overlay_label: Label = $FlyView/Overlay/Label
@onready var _fly_draw: Node2D = $FlyView/FlyOverlay

var world_seed: int = 0
var spec: WorldSpec = null
var current_view: int = 1
var selected_biome := Vector2i.ZERO
var selected_room := 0
var _room_graphs: RoomGraph = null   ## per-session BiomeGraph cache; reset on reseed

var _hist: Array[int] = []           ## seed history for [ / ]
var _hist_pos := -1
var _player: CharacterBody2D = null  ## drop-in player (fly view), null while flying
var _layout_ms := 0.0
var _graphs_ms := 0.0

var _stats_label: Label
var _legend_label: Label
var _bm_dd: OptionButton
var _bm_seeds: Array[int] = []


func _ready() -> void:
	# The game viewport is 320×180 with canvas_items stretch — unusable for a debug UI.
	# This scene renders in native window pixels instead; views lay out from window size.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_seed_edit.text_submitted.connect(_on_seed_submitted)
	_streamer.config = config
	_streamer.target = _flycam
	_streamer.streaming = false   # only view 4 streams
	_build_extra_ui()
	_restore_state()
	if world_seed == 0:
		world_seed = randi()   # UI-side reroll, not generation code — global RNG is fine here
	_push_history(world_seed)
	_rebuild()
	_switch_view(current_view)


func _exit_tree() -> void:
	_save_state()


func _process(_dt: float) -> void:
	if current_view != 4 or _streamer.world_spec == null:
		return
	var focus: Node2D = _player if _player != null else _flycam
	var chunk_px := config.chunk_tiles * GameConstants.PX_PER_TILE
	var gp := focus.global_position
	var cc := Vector2i(floori(gp.x / chunk_px), floori(gp.y / chunk_px))
	var t := Vector2i((gp / GameConstants.PX_PER_TILE).floor())
	var crumb := _breadcrumb(t)
	var mode := "[P] exit player  hp %d/%d" % [_player.health, _player.max_health] \
			if _player != null else "[P] drop in as player"
	_overlay_label.text = "%s\nchunk %d,%d  loaded %d   cache %d/%d   assembly %.2f ms\n%s   [O]bounds [G]grid [H]heat [V]borders" % [
			crumb, cc.x, cc.y, _streamer.loaded_chunks(),
			_streamer.cache_hits, _streamer.cache_misses,
			_streamer.last_assembly_usec / 1000.0, mode]


## "biome | room type tier/depth" for a world tile — the fly view's you-are-here line.
func _breadcrumb(t: Vector2i) -> String:
	var rspec := _streamer.room_spec_at_tile(t.x, t.y)
	if rspec == null:
		return "tile %d,%d — outside the world" % [t.x, t.y]
	return "tile %d,%d   biome %s   room %s @%s  tier %d  depth %d/%d" % [t.x, t.y,
			rspec.biome_id, rspec.type_id, rspec.origin_slot, rspec.tier(), rspec.depth,
			rspec.biome_max_depth]


# --- Input ------------------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_R:
			_apply_seed(randi())
		KEY_1, KEY_2, KEY_3, KEY_4:
			_switch_view(key.keycode - KEY_1 + 1)
		KEY_ENTER, KEY_KP_ENTER:
			_drill_in()
		KEY_ESCAPE:
			_drill_out()
		KEY_BRACKETLEFT:
			_history_step(-1)
		KEY_BRACKETRIGHT:
			_history_step(1)
		KEY_C:
			DisplayServer.clipboard_set(str(world_seed))
			print("worldgen debug: seed %d copied" % world_seed)
		KEY_B:
			_bookmark_seed()
		KEY_T:
			_teleport_to_selection()
		KEY_L:
			_legend_label.visible = not _legend_label.visible
			_save_state()
		KEY_F2:
			_stats_label.visible = not _stats_label.visible
			_save_state()
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if current_view == 2:
				_move_selection(key.keycode)
		KEY_P:
			if current_view == 3:
				_room_view.toggle_protected()
			elif current_view == 4:
				_toggle_drop_in()
		KEY_M:
			if current_view == 3:
				_room_view.toggle_reach()
		KEY_O:
			if current_view == 4:
				_fly_draw.show_bounds = not _fly_draw.show_bounds
				_save_state()
		KEY_G:
			if current_view == 4:
				_fly_draw.show_grid = not _fly_draw.show_grid
				_save_state()
		KEY_H:
			if current_view == 4:
				_fly_draw.show_heat = not _fly_draw.show_heat
				_save_state()
		KEY_V:
			if current_view == 4:
				_fly_draw.show_borders = not _fly_draw.show_borders
				_save_state()


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if current_view == 1:
		var cell: Vector2i = _world_view.cell_at_screen_pos(mb.position)
		if cell.x >= 0:
			_select_biome(cell)
			if mb.double_click:
				_switch_view(2)
	elif current_view == 2:
		var cell: Vector2i = _biome_view.cell_at_screen_pos(mb.position)
		if cell.x >= 0:
			if cell != selected_biome:
				_select_biome(cell)
			return
		var room: int = _biome_view.room_at_screen_pos(mb.position)
		if room >= 0:
			selected_room = room
			_save_state()
			_refresh_biome_view()
			if mb.double_click:
				_switch_view(3)


func _select_biome(cell: Vector2i) -> void:
	selected_biome = cell
	selected_room = 0
	_save_state()
	_world_view.set_selected(cell)
	if current_view == 2:
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
		_select_biome(next)


# --- Drill-down navigation ----------------------------------------------------------------------

func _drill_in() -> void:
	match current_view:
		1:
			if spec != null and spec.biome_at(selected_biome) != &"":
				_switch_view(2)
		2:
			if _selected_graph() != null:
				_switch_view(3)
		3:
			_teleport_to_selection()


func _drill_out() -> void:
	match current_view:
		4:
			if _player != null:
				_toggle_drop_in()   # first Esc returns to the fly camera
			else:
				_switch_view(3)
		3:
			_switch_view(2)
		2:
			_switch_view(1)


## Fly the camera to the current selection (biome centre in view 1, room centre in 2/3)
## and enter the fly view there.
func _teleport_to_selection() -> void:
	if spec == null:
		return
	var px := GameConstants.PX_PER_TILE
	var pos := Vector2.ZERO
	var graph := _selected_graph()
	if current_view >= 2 and graph != null and not graph.rooms.is_empty():
		var r: RoomSpec = graph.rooms[clampi(selected_room, 0, graph.rooms.size() - 1)]
		pos = (Vector2(r.origin_slot) + Vector2(r.size_slots) * 0.5) * config.room_slot_tiles * px
	else:
		var bid := spec.biome_at(selected_biome)
		if bid == &"":
			return
		pos = (Vector2(selected_biome) + Vector2(0.5, 0.5)) * config.biome_slots \
				* config.room_slot_tiles * px
	_flycam.global_position = pos
	_switch_view(4)


# --- Seed management ------------------------------------------------------------------------------

func _on_seed_submitted(text: String) -> void:
	_seed_edit.release_focus()
	_apply_seed(text.to_int())


func _apply_seed(s: int, from_history := false) -> void:
	world_seed = s
	if not from_history:
		_push_history(s)
	_rebuild()
	_save_state()


func _push_history(s: int) -> void:
	if _hist_pos >= 0 and _hist_pos < _hist.size() and _hist[_hist_pos] == s:
		return
	_hist.resize(_hist_pos + 1)   # branching forgets the redo tail, like an undo stack
	_hist.append(s)
	_hist_pos = _hist.size() - 1


func _history_step(dir: int) -> void:
	var next := _hist_pos + dir
	if next < 0 or next >= _hist.size():
		return
	_hist_pos = next
	_apply_seed(_hist[_hist_pos], true)


func _bookmark_seed() -> void:
	var note := "%s  view %d  biome %s" % [Time.get_date_string_from_system(), current_view,
			spec.biome_at(selected_biome) if spec != null else &"?"]
	DebugState.set_value("wg_bookmarks", str(world_seed), note)
	print("worldgen debug: bookmarked seed %d (%s)" % [world_seed, note])
	_refresh_bookmarks()


func _refresh_bookmarks() -> void:
	_bm_dd.clear()
	_bm_seeds.clear()
	_bm_dd.add_item("bookmarks")   # placeholder entry so the button reads as a menu
	for key in DebugState.keys("wg_bookmarks"):
		_bm_seeds.append(key.to_int())
		_bm_dd.add_item("%s — %s" % [key, DebugState.get_value("wg_bookmarks", key, "")])
	_bm_dd.selected = 0


func _on_bookmark_picked(idx: int) -> void:
	if idx <= 0 or idx - 1 >= _bm_seeds.size():
		return
	_bm_dd.selected = 0
	_apply_seed(_bm_seeds[idx - 1])


# --- Rebuild / views ------------------------------------------------------------------------------

func _rebuild() -> void:
	if _player != null:
		_toggle_drop_in()   # never keep a live player across a world swap
	var t0 := Time.get_ticks_usec()
	spec = WorldLayout.build(world_seed, config)
	_layout_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if spec == null:
		_seed_label.text = "seed %d — LAYOUT FAILED (unsatisfiable adjacency rules?)" % world_seed
		return
	_room_graphs = RoomGraph.new()   # fresh cache — the whole world changed
	t0 = Time.get_ticks_usec()
	for p in spec.placements:
		_room_graphs.get_biome_graph(spec, p.id, config)   # warm the cache + time it
	_graphs_ms = (Time.get_ticks_usec() - t0) / 1000.0
	selected_biome = Vector2i(clampi(selected_biome.x, 0, spec.grid_w - 1),
			clampi(selected_biome.y, 0, spec.grid_h - 1))
	_world_view.set_data(spec, config)
	_world_view.set_selected(selected_biome)
	_fly_draw.set_data(spec, config, _room_graphs)
	_refresh_stats()
	_refresh_header()
	if current_view == 2:
		_refresh_biome_view()
	elif current_view == 3:
		_refresh_room_view()
	elif current_view == 4:
		_streamer.build_world(world_seed)   # rebuild the streamed world in place


## Graph of the biome owning the selected cell, or null for an unclaimed (sealed) cell.
func _selected_graph() -> BiomeGraph:
	if spec == null:
		return null
	var bid := spec.biome_at(selected_biome)
	if bid == &"":
		return null
	return _room_graphs.get_biome_graph(spec, bid, config)


func _refresh_biome_view() -> void:
	if spec == null:
		return
	_biome_view.set_data(spec, config, _selected_graph(), selected_biome, selected_room)


## Build the selected room's REAL output (same call the streamer makes) and show it.
func _refresh_room_view() -> void:
	var graph := _selected_graph()
	if graph == null or graph.rooms.is_empty():
		_room_view.set_data(null, null)
		return
	selected_room = clampi(selected_room, 0, graph.rooms.size() - 1)
	var rspec: RoomSpec = graph.rooms[selected_room]
	_room_view.set_data(rspec, RoomBuilder.build(rspec, config, world_seed))


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
	_refresh_header()
	_refresh_legend()
	_save_state()


func _refresh_header() -> void:
	_seed_label.text = "seed %d   view %d   [R]eroll [[/]]history [C]opy [B]ookmark  [Enter]drill [Esc]back [T]eleport  [L]egend [F2]stats" % [
			world_seed, current_view]


## Enter/leave fly mode: the fly camera and streaming loop only run in view 4. Loaded chunks are
## kept when leaving (cheap; re-shown on return); a reseed while away still rebuilds on re-entry.
## CanvasLayer children (the HUD + overlay labels) ignore their Node2D ancestor's `visible` —
## Godot only hides them if their OWN `visible` is set — so FlyView.visible=false alone left
## their text drawing on top of the other views, looking like two views superimposed.
func _set_fly_active(on: bool) -> void:
	if on and (_streamer.world_spec == null or _streamer.world_seed != world_seed):
		_streamer.build_world(world_seed)
	if not on and _player != null:
		_toggle_drop_in()
	_streamer.streaming = on
	_flycam.set_process(on and _player == null)
	_fly_cam2d.enabled = on and _player == null
	_fly_hud.visible = on and _player == null
	_fly_overlay.visible = on
	if on and _player == null:
		_fly_cam2d.zoom = Vector2(2, 2)   # 8px tiles visible
		_fly_cam2d.make_current()


# --- Drop-in player -------------------------------------------------------------------------------

## Swap between the fly camera and a real, invulnerable player at the same spot. The player
## streams the world, fights real enemies (give gear via the ` console), and hands the
## position back to the camera on exit.
func _toggle_drop_in() -> void:
	if _player == null:
		_player = PLAYER_SCENE.instantiate()
		_player.debug_never_die = true   # a lab death must never wipe the real save
		var pos := _streamer.nearest_walkable(_flycam.global_position)
		_player.global_position = pos if pos != Vector2.INF else _flycam.global_position
		_entities.add_child(_player)
		_player.grant_spawn_grace()
		_flycam.remove_from_group("player")   # enemies must hunt the player, not the camera
		_streamer.target = _player
		var cam: Camera2D = _player.get_node("Camera2D")
		# Content scaling is disabled in this scene, so the game's 320×180 view must be
		# zoomed up by hand to keep the play view life-sized.
		var win := get_window().size
		var z := maxf(1.0, floorf(minf(win.x / 320.0, win.y / 180.0)))
		cam.zoom = Vector2(z, z)
		cam.make_current()
		_flycam.set_process(false)
		_flycam.visible = false   # its yellow view-box would linger at the entry point
		_fly_cam2d.enabled = false
		_fly_hud.visible = false
	else:
		_flycam.global_position = _player.global_position
		_player.queue_free()
		_player = null
		_flycam.add_to_group("player")
		_streamer.target = _flycam
		_flycam.set_process(true)
		_flycam.visible = true
		_fly_cam2d.enabled = true
		_fly_cam2d.make_current()
		_fly_hud.visible = true


# --- Extra UI (stats, legend, seed toolbar) -------------------------------------------------------

func _build_extra_ui() -> void:
	var ui: CanvasLayer = $UI

	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -420.0
	bar.offset_top = 46.0
	bar.offset_bottom = 74.0
	ui.add_child(bar)
	var back := Button.new()
	back.text = "< seed"
	back.pressed.connect(func(): _history_step(-1))
	bar.add_child(back)
	var fwd := Button.new()
	fwd.text = "seed >"
	fwd.pressed.connect(func(): _history_step(1))
	bar.add_child(fwd)
	var copy := Button.new()
	copy.text = "copy"
	copy.pressed.connect(func(): DisplayServer.clipboard_set(str(world_seed)))
	bar.add_child(copy)
	var bm := Button.new()
	bm.text = "bookmark"
	bm.pressed.connect(_bookmark_seed)
	bar.add_child(bm)
	_bm_dd = OptionButton.new()
	_bm_dd.fit_to_longest_item = false
	_bm_dd.item_selected.connect(_on_bookmark_picked)
	bar.add_child(_bm_dd)
	_refresh_bookmarks()

	_stats_label = Label.new()
	_stats_label.position = Vector2(16, 84)
	_stats_label.add_theme_font_size_override("font_size", 13)
	_stats_label.modulate = Color(0.85, 0.95, 1.0)
	_stats_label.visible = false
	ui.add_child(_stats_label)

	_legend_label = Label.new()
	_legend_label.anchor_top = 1.0
	_legend_label.anchor_bottom = 1.0
	_legend_label.offset_left = 16.0
	_legend_label.offset_top = -150.0
	_legend_label.add_theme_font_size_override("font_size", 13)
	_legend_label.modulate = Color(1.0, 0.95, 0.7)
	_legend_label.visible = false
	ui.add_child(_legend_label)


func _refresh_stats() -> void:
	if spec == null:
		return
	var lines: Array[String] = ["layout %.1f ms   graphs %.1f ms" % [_layout_ms, _graphs_ms]]
	for p in spec.placements:
		var graph := _room_graphs.get_biome_graph(spec, p.id, config)
		var counts: Dictionary = {}
		var max_depth := 0
		for r in graph.rooms:
			counts[r.type_id] = counts.get(r.type_id, 0) + 1
			max_depth = maxi(max_depth, r.depth)
		lines.append("%s  %s cells  %d rooms  max depth %d" % [p.id, p.rect.size,
				graph.rooms.size(), max_depth])
		var ids := counts.keys()
		ids.sort()
		for tid in ids:
			lines.append("    %s x%d" % [tid, counts[tid]])
	_stats_label.text = "\n".join(lines)


const LEGENDS := {
	1: "world view — colored cells: biomes (dark = sealed void) · black frames: biome regions\nred ticks: border-contract door crossings · gold dots: world-unique rooms\nclick: select biome · double-click/Enter: open biome view",
	2: "biome view — one rect per room, hue = room TYPE, hot = higher tier\ncyan outline: quota (guaranteed) type · gold: world-unique · white flash: selected\npassages — white: tree edge · yellow: loop · red: border contract; short tick = door, long = open\nclick room: select · double-click/Enter: room view · corner map: switch biome",
	3: "room view — grey: wall · dark: floor · mid-grey: blocker · green: decor floor\ncyan wash [P]: PROTECTED tiles · green wash [M]: reachable tiles\nred dots: enemy spawns (list on the right) · gold: features · red/white edge marks: passages",
	4: "fly view — WASD/arrows fly · wheel zoom · yellow box: real 320x180 play view\n[O] room bounds+tags · [G] chunk grid · [H] tier heatmap (green0..red3) · [V] biome borders\n[P] drop in as a real (invulnerable) player at the camera — ` console: give/equip gear",
}


func _refresh_legend() -> void:
	_legend_label.text = LEGENDS.get(current_view, "")


# --- Persistence / deep links ---------------------------------------------------------------------

func _restore_state() -> void:
	world_seed = DebugState.get_value("worldgen_debug", "seed", 0)
	current_view = DebugState.get_value("worldgen_debug", "view", 1)
	selected_biome = DebugState.get_value("worldgen_debug", "biome", Vector2i.ZERO)
	selected_room = DebugState.get_value("worldgen_debug", "room", 0)
	_flycam.global_position = DebugState.get_value("worldgen_debug", "cam", Vector2.ZERO)
	_fly_draw.show_bounds = DebugState.get_value("worldgen_debug", "ov_bounds", false)
	_fly_draw.show_grid = DebugState.get_value("worldgen_debug", "ov_grid", false)
	_fly_draw.show_heat = DebugState.get_value("worldgen_debug", "ov_heat", false)
	_fly_draw.show_borders = DebugState.get_value("worldgen_debug", "ov_borders", true)
	_stats_label.visible = DebugState.get_value("worldgen_debug", "stats", false)
	_legend_label.visible = DebugState.get_value("worldgen_debug", "legend", false)
	# CLI deep-links override the stored state.
	world_seed = DebugState.cli_int("seed", world_seed)
	current_view = clampi(DebugState.cli_int("view", current_view), 1, 4)
	var pos := DebugState.cli_vec2i("pos", Vector2i(-1, -1))
	if pos.x >= 0:
		_flycam.global_position = (Vector2(pos) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE


func _save_state() -> void:
	DebugState.set_value("worldgen_debug", "seed", world_seed)
	DebugState.set_value("worldgen_debug", "view", current_view)
	DebugState.set_value("worldgen_debug", "biome", selected_biome)
	DebugState.set_value("worldgen_debug", "room", selected_room)
	DebugState.set_value("worldgen_debug", "cam",
			(_player.global_position if _player != null else _flycam.global_position))
	DebugState.set_value("worldgen_debug", "ov_bounds", _fly_draw.show_bounds)
	DebugState.set_value("worldgen_debug", "ov_grid", _fly_draw.show_grid)
	DebugState.set_value("worldgen_debug", "ov_heat", _fly_draw.show_heat)
	DebugState.set_value("worldgen_debug", "ov_borders", _fly_draw.show_borders)
	DebugState.set_value("worldgen_debug", "stats", _stats_label.visible)
	DebugState.set_value("worldgen_debug", "legend", _legend_label.visible)
