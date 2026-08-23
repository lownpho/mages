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
## and fight the actual room; use the ` console to `give`/`equip` gear. Doors work for the
## drop-in player: a warp door moves it beside its twin, a dungeon config's stairs walk the floors
## (each floor is a reseed, so every view follows the player down), and a gate into another world
## — the mycelium one — swaps the browsed config instead of dropping the tool into the real game.
## Nothing in here ever leaves the tool.
##
## F2 stats sidebar (per-biome room/type/depth counts + build timings), L legend.
## Everything (seed, view, selection, camera, toggles) persists across runs; CLI deep-links:
##   godot --path game res://debug/worldgen/worldgen_debug.tscn -- seed=123 view=4 pos=40,20
## `config=mycelium` (or a full res:// path) browses a different world config entirely; the
## toolbar dropdown does the same from inside the editor, and the pick is remembered.

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
var _floor := 1                      ## dungeon floor the fly view is on (1 for a flat world)
var _floor_base := 0                 ## the tool's own seed; for a dungeon config, the RUN every floor derives from
var _return_config: GenConfig = null ## world walked out of through a door, for the way back
var _floor_config: GenConfig = null   ## the current floor's content pool; `config` stays the dungeon
var _layout_ms := 0.0
var _graphs_ms := 0.0

var _stats_label: Label
var _legend_label: Label
var _bm_dd: OptionButton
var _bm_seeds: Array[int] = []
var _cfg_dd: OptionButton
var _cfg_paths: PackedStringArray = []


func _ready() -> void:
	# The game viewport is 320×180 with canvas_items stretch — unusable for a debug UI.
	# This scene lays out in window pixels instead, upscaled so the 8px theme font reads like
	# it does in the combat lab. Everything below is in logical (pre-scale) px.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_factor = DebugState.UI_SCALE
	_seed_edit.text_submitted.connect(_on_seed_submitted)
	_apply_cli_config()
	_streamer.config = config
	_streamer.target = _flycam
	_streamer.streaming = false   # only view 4 streams
	_build_extra_ui()
	_restore_state()
	if world_seed == 0:
		world_seed = randi()   # UI-side reroll, not generation code — global RNG is fine here
	_floor_base = world_seed
	_push_history(_floor_base)
	world_seed = _seed_for_floor(1)
	GlobalEvent.warp_requested.connect(_on_warp_requested)
	GlobalEvent.floor_change_requested.connect(_on_floor_change)
	# A scene-change door (the mimic deepwood's mycelium gate) would drop the tool into the real
	# game — and walking out of THAT lands in world.tscn, which persists over the player's run.
	# So the tool takes the door itself: it opens the destination's world HERE. Clearing
	# target_scene is what stops door.gd doing its own scene change (it warns instead, harmlessly).
	_entities.child_entered_tree.connect(func(n: Node) -> void:
		if not (n is Door) or n.target_scene == null:
			return
		var dest: PackedScene = n.target_scene
		n.target_scene = null
		n.body_entered.connect(func(_b: Node2D) -> void: _enter_world(dest)))
	_rebuild()
	_switch_view(current_view)


## `config=<name>` swaps the whole generator config — a bare name resolves to
## world_content/<name>_gen_config.tres, so a side world (the mycelium dungeon) can be
## browsed without editing the scene. With no CLI arg the last toolbar pick is restored.
## Must run before the streamer takes its copy.
func _apply_cli_config() -> void:
	var arg := DebugState.cli_arg("config")
	var path: String = DebugState.get_value("worldgen_debug", "config", "")
	if arg != "":
		path = arg if arg.begins_with("res://") else "res://world_content/%s_gen_config.tres" % arg
	if path == "" or path == config.resource_path:
		return
	var c := ResourceLoader.load(path)
	if c is GenConfig:
		config = c
	else:
		push_error("worldgen_debug: config %s did not load a GenConfig" % path)


## Swap the world the tool browses. The streamer's built world is stale, so it is dropped —
## _set_fly_active rebuilds it on the next visit to view 4.
func _on_config_picked(idx: int) -> void:
	if idx < 0 or idx >= _cfg_paths.size() or _cfg_paths[idx] == config.resource_path:
		return
	var c := ResourceLoader.load(_cfg_paths[idx])
	if not (c is GenConfig):
		push_error("worldgen_debug: %s is not a GenConfig" % _cfg_paths[idx])
		return
	_use_config(c)


## Browse another world: floor 1 of it, selection reset, everything rebuilt. `keep_player` is for
## a door walked through — the player stays in play and is put down on the far side by the caller.
func _use_config(c: GenConfig, keep_player := false) -> void:
	config = c
	_cfg_dd.selected = maxi(0, _cfg_paths.find(c.resource_path))
	_streamer.config = c
	_streamer.world_spec = null
	_floor = 1                          # the new config may stack floors where the old one did not
	world_seed = _seed_for_floor(1)
	selected_biome = Vector2i.ZERO
	selected_room = 0
	_rebuild(keep_player)
	_save_state()


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
			DisplayServer.clipboard_set(str(_floor_base))
			print("worldgen debug: seed %d copied" % _floor_base)
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
	_floor_base = s
	_floor = 1          # a hand-picked seed is the run, entered at its first floor
	world_seed = _seed_for_floor(1)
	if not from_history:
		_push_history(s)
	_rebuild()
	_save_state()


## The seed a floor generates from. A flat config has one world and one seed; a dungeon config
## makes the tool's seed the RUN seed, with every floor — floor 1 included — derived from it, so
## the tool browses exactly the floors the game builds for that run, and walking a stair down and
## back up returns to the floor you left.
func _seed_for_floor(n: int) -> int:
	return DungeonFloors.floor_seed(_floor_base, n) if config.floors > 1 else _floor_base


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
	DebugState.set_value("wg_bookmarks", str(_floor_base), note)
	print("worldgen debug: bookmarked seed %d (%s)" % [_floor_base, note])
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

## `keep_player` is for a stair: the drop-in player survives the swap because it is put down on
## the new floor in the same breath. Any other reseed drops it — it would be left standing in a
## world that no longer exists.
func _rebuild(keep_player := false) -> void:
	if _player != null and not keep_player:
		_toggle_drop_in()
	# A dungeon floor swaps the whole content pool, so everything that reads ROOM TYPES below asks
	# the floor's config; `config` stays the dungeon and keeps answering for dials and depth.
	_floor_config = DungeonFloors.config_for(config, _floor)
	_streamer.config = _floor_config
	var t0 := Time.get_ticks_usec()
	spec = WorldLayout.build(world_seed, _floor_config)
	_layout_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if spec == null:
		_seed_label.text = "seed %d — LAYOUT FAILED (unsatisfiable adjacency rules?)" % _floor_base
		return
	_room_graphs = RoomGraph.new()   # fresh cache — the whole world changed
	t0 = Time.get_ticks_usec()
	for p in spec.placements:
		_room_graphs.get_biome_graph(spec, p.id, _floor_config)   # warm the cache + time it
	_graphs_ms = (Time.get_ticks_usec() - t0) / 1000.0
	selected_biome = Vector2i(clampi(selected_biome.x, 0, spec.grid_w - 1),
			clampi(selected_biome.y, 0, spec.grid_h - 1))
	_world_view.set_data(spec, _floor_config)
	_world_view.set_selected(selected_biome)
	_fly_draw.set_data(spec, _floor_config, _room_graphs)
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
	return _room_graphs.get_biome_graph(spec, bid, _floor_config)


func _refresh_biome_view() -> void:
	if spec == null:
		return
	_biome_view.set_data(spec, _floor_config, _selected_graph(), selected_biome, selected_room)


## Build the selected room's REAL output (same call the streamer makes) and show it.
func _refresh_room_view() -> void:
	var graph := _selected_graph()
	if graph == null or graph.rooms.is_empty():
		_room_view.set_data(null, null)
		return
	selected_room = clampi(selected_room, 0, graph.rooms.size() - 1)
	var rspec: RoomSpec = graph.rooms[selected_room]
	_room_view.set_data(rspec, RoomBuilder.build(rspec, _floor_config, world_seed))


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
	# The seed on screen is the one you type: the run, not the floor it derives.
	var floors := "   floor %d" % _floor if config.floors > 1 else ""
	_seed_label.text = "seed %d%s   view %d   [R]eroll [[/]]history [C]opy [B]ookmark  [Enter]drill [Esc]back [T]eleport  [L]egend [F2]stats" % [
			_floor_base, floors, current_view]


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
		_fly_cam2d.zoom = Vector2(2, 2) / DebugState.UI_SCALE   # 2x on screen after the upscale
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
		var win := get_viewport_rect().size
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


# --- Doors ----------------------------------------------------------------------------------------
# Only the drop-in player trips these — the fly camera is no body, so it still passes through.

func _on_warp_requested(target_slot: Vector2i, body: Node2D, heading: Vector2i) -> void:
	var dest := _streamer.door_exit_position(target_slot, heading)
	if dest != Vector2.INF:
		body.global_position = dest


## Walking a door into another world: the destination scene carries the GenConfig it streams, so
## the tool switches to that world and puts the player down at its entrance stair (its own spawn
## if it has no floors). The world walked out of is remembered, so the ladder's ends come back.
func _enter_world(dest: PackedScene) -> void:
	if _player == null:
		return
	var cfg := _config_in(dest)
	if cfg == null:
		push_warning("worldgen debug: %s streams no GenConfig — nowhere to go" % dest.resource_path)
		return
	var from := config
	_use_config(cfg, true)
	_return_config = from
	_player.global_position = DungeonFloors.stair_position(_streamer, config.stair_up_room) \
			if config.floors > 1 else _streamer.find_spawn_position()
	_refresh_header()


## The GenConfig a world scene streams, read off a bare instance — never added to the tree, so
## nothing in it runs.
static func _config_in(scene: PackedScene) -> GenConfig:
	var root := scene.instantiate()
	var cfg: GenConfig = null
	for n in root.find_children("*", "", true, false):
		if n is WorldStreamer:
			cfg = n.config
			break
	root.free()
	return cfg


## A stair door: a floor is just another seed, so the tool takes the change as a reseed and every
## view follows the player down instead of still showing the floor above. The player keeps
## playing, put down at the stair it did NOT take. Both ends of the ladder leave for the
## overworld, which the tool has no way to show — those two simply do nothing.
func _on_floor_change(delta: int, _body: Node2D) -> void:
	if _player == null:
		return
	var n := DungeonFloors.next_floor(config, _floor, delta)
	if n == 0:
		# Both ends of the ladder leave for the world the gate was in. The tool has no gate door
		# to land on over there, so it uses that world's spawn.
		if _return_config != null:
			var back := _return_config
			_use_config(back, true)
			_return_config = null
			_player.global_position = _streamer.find_spawn_position()
			print("worldgen debug: left the dungeon — %s, at its spawn" % back.resource_path)
			_refresh_header()
		return
	_floor = n
	world_seed = _seed_for_floor(n)
	_rebuild(true)
	_player.global_position = DungeonFloors.stair_position(_streamer,
			config.stair_up_room if delta > 0 else config.stair_down_room)
	_refresh_header()


# --- Extra UI (stats, legend, seed toolbar) -------------------------------------------------------

func _build_extra_ui() -> void:
	var ui: CanvasLayer = $UI

	var bar := HBoxContainer.new()
	bar.theme = DebugUi.theme()
	_seed_edit.theme = bar.theme
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -520.0
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
	copy.pressed.connect(func(): DisplayServer.clipboard_set(str(_floor_base)))
	bar.add_child(copy)
	var bm := Button.new()
	bm.text = "bookmark"
	bm.pressed.connect(_bookmark_seed)
	bar.add_child(bm)
	_cfg_dd = OptionButton.new()
	_cfg_paths = DebugContent.scan_gen_configs()
	for path in _cfg_paths:
		var label := path.get_file().trim_suffix("gen_config.tres").trim_suffix("_")
		_cfg_dd.add_item(label if label != "" else "world")
	_cfg_dd.selected = _cfg_paths.find(config.resource_path)
	_cfg_dd.item_selected.connect(_on_config_picked)
	bar.add_child(_cfg_dd)
	_bm_dd = OptionButton.new()
	_bm_dd.fit_to_longest_item = false
	_bm_dd.item_selected.connect(_on_bookmark_picked)
	bar.add_child(_bm_dd)
	_refresh_bookmarks()

	_stats_label = Label.new()
	_stats_label.position = Vector2(16, 84)
	_stats_label.modulate = Color(0.85, 0.95, 1.0)
	_stats_label.visible = false
	ui.add_child(_stats_label)

	_legend_label = Label.new()
	_legend_label.anchor_top = 1.0
	_legend_label.anchor_bottom = 1.0
	_legend_label.offset_left = 16.0
	_legend_label.offset_top = -150.0
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
	4: "fly view — WASD/arrows fly · wheel zoom · yellow box: real 320x180 play view\n[O] room bounds+tags · [G] chunk grid · [H] tier heatmap (green0..red3) · [V] biome borders\n[P] drop in as a real (invulnerable) player at the camera — ` console: give/equip gear\ndoors work for the drop-in: warps hop to their twin, stairs walk the dungeon's floors, gates swap world",
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
	DebugState.set_value("worldgen_debug", "config", config.resource_path)
	DebugState.set_value("worldgen_debug", "seed", _floor_base)
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
