extends Control
## The strip minimap: draws the shared MapState's discovered-world textures with the player fixed
## at the centre, north-up. The state (fog-of-war discovery, textures, markers) is owned by
## GlobalMap; this widget only renders the active one and steps its own zoom. The widget never
## resizes — +/-, the wheel while hovering it, or Y + dpad up/down on a pad, step tiles-per-pixel
## (MapState.ZOOM_TILES_PER_PX; off the map the wheel cycles the spell page instead). Walls
## render at every zoom from a per-level majority-downsampled image, so explored dead ends stay
## flagged when zoomed out. Live enemies show only inside discovered rooms, so nothing leaks
## through fog of war.

const ENEMIES_MAX_TPP := 4  ## live enemy dots hidden at zooms coarser than this

# Marker colors, all Zughy 32.
const COLOR_UNKNOWN := Palette.BLACK
const COLOR_PLAYER := Palette.WHITE
const COLOR_ENEMY := Palette.RED
const COLOR_BOSS := Palette.YELLOW
const COLOR_FEATURE := Palette.CYAN
const COLOR_FOUNTAIN := Palette.PINK
const COLOR_DOOR := Palette.BLUE
const COLOR_SIGN := Palette.GREEN
const COLOR_NPC := Palette.PURPLE
const COLOR_PIN := Palette.ORANGE
const PIN_PX := 2  ## pin marker size in widget pixels

var _state: MapState = null
var _player: Node2D = null
var _zoom_idx := 0


func _ready() -> void:
	GlobalMap.map_changed.connect(_on_map_changed)
	GlobalMap.pins_changed.connect(queue_redraw)
	if GlobalMap.active != null:   # world already up (widget re-added, or late scene load)
		_on_map_changed()
	set_process(false)


func _on_map_changed() -> void:
	_state = GlobalMap.active
	_player = get_tree().get_first_node_in_group("player")
	set_process(_state != null)
	queue_redraw()


func _process(_dt: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	queue_redraw()   # enemies move even when the player doesn't; discovery is GlobalMap's job


## The +/- keys zoom wherever the cursor is; the wheel only zooms while hovering the widget
## (see _gui_input), since elsewhere it cycles the player's spell page. On a pad it's the
## Y + dpad up/down chord (see _pad_chord_dir).
func _unhandled_input(event: InputEvent) -> void:
	if _state == null:
		return
	if event.is_action_pressed("minimap_zoom_in"):
		_step_zoom(-1)
	elif event.is_action_pressed("minimap_zoom_out"):
		_step_zoom(1)
	else:
		var dir := _pad_chord_dir(event)
		if dir != 0:
			_step_zoom(dir)
			get_viewport().set_input_as_handled()


## Zoom direction for the pad chord — hold Y ("minimap_zoom_mod") and tap dpad up/down — or 0
## when the event isn't it. The dpad can't zoom on its own: bare, it belongs to HUD slot focus
## and to whatever panel is open, so the strip only listens while the modifier is down. Joypad
## events only, since the same ui_up/ui_down carry the arrow keys, which stay the menus'. The
## chord also stands down whenever the UI has captured input: the strip is then either behind
## the open full map (which zooms on its own bare dpad) or under slot navigation.
func _pad_chord_dir(event: InputEvent) -> int:
	if not event is InputEventJoypadButton or GlobalInput.ui_captured \
			or not Input.is_action_pressed("minimap_zoom_mod"):
		return 0
	if event.is_action_pressed("ui_up"):
		return -1
	if event.is_action_pressed("ui_down"):
		return 1
	return 0


func _step_zoom(dir: int) -> void:
	var ni := clampi(_zoom_idx + dir, 0, MapState.ZOOM_TILES_PER_PX.size() - 1)
	if ni == _zoom_idx:
		return
	_zoom_idx = ni
	queue_redraw()


## Left-click a spot on the minimap to drop a pin there; click near an existing pin to clear it.
## The click's widget-local position maps back to a world tile through the same centre/zoom the
## draw uses. (Runs as _gui_input because the widget's mouse_filter stops events at the GUI layer.)
## The wheel zooms here too, and is consumed so it doesn't also flip the spell page.
func _gui_input(event: InputEvent) -> void:
	if _state == null or _player == null or not is_instance_valid(_player):
		return
	if event is InputEventMouseButton and event.pressed \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP
				or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if GlobalInput.wheel_fresh:
			_step_zoom(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		accept_event()   # swallowed ones too, so they can't reach the page flip
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var tpp := MapState.ZOOM_TILES_PER_PX[_zoom_idx]
		var center := _player.global_position / GameConstants.PX_PER_TILE
		var world: Vector2 = center + (event.position - size * 0.5) * tpp
		GlobalMap.toggle_pin(Vector2i(world.floor()), tpp * 2)   # ~2 px click tolerance
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_UNKNOWN)
	if _state == null or _player == null or not is_instance_valid(_player):
		return
	var tpp := MapState.ZOOM_TILES_PER_PX[_zoom_idx]
	var center := _player.global_position / GameConstants.PX_PER_TILE   # in tiles
	var region := Rect2(center - size * tpp * 0.5, size * tpp)          # visible world tiles

	for image in _state.images_in(region, tpp):
		_draw_layer(image.floor_texture, region, tpp, 1, image.world_rect)
		_draw_layer(image.wall_texture, region, tpp, image.texel_tiles, image.world_rect)

	for m in _state.markers:
		var color := COLOR_FEATURE
		match m["kind"]:
			MapState.MARKER_BOSS: color = COLOR_BOSS
			MapState.MARKER_FOUNTAIN: color = COLOR_FOUNTAIN
			MapState.MARKER_DOOR: color = COLOR_DOOR
			MapState.MARKER_SIGN: color = COLOR_SIGN
			MapState.MARKER_NPC: color = COLOR_NPC
		_draw_marker(Vector2(m["tile"]) + Vector2(0.5, 0.5), region, tpp, color,
				2 if m["kind"] == MapState.MARKER_BOSS else 1, m.get("project", false))
	if tpp <= ENEMIES_MAX_TPP:
		for e in get_tree().get_nodes_in_group("enemies"):
			var et: Vector2 = e.global_position / GameConstants.PX_PER_TILE
			if _state.is_tile_discovered(Vector2i(et.floor())):
				_draw_marker(et, region, tpp, COLOR_ENEMY, 1)

	for p in _state.pins:
		_draw_pin(Vector2(p) + Vector2(0.5, 0.5), region, tpp)

	draw_rect(Rect2((size * 0.5).floor(), Vector2.ONE), COLOR_PLAYER)


## Blit the part of a world texture visible through `region` (in tiles) onto the widget,
## clamped to the world so out-of-bounds sampling never smears edge pixels. `texel_tiles` is
## how many world tiles one texel spans (1 for full-res images, tpp for wall level images).
func _draw_layer(tex: ImageTexture, region: Rect2, tpp: int, texel_tiles: int,
		world_rect: Rect2i) -> void:
	var vis := region.intersection(Rect2(world_rect))
	if not vis.has_area():
		return
	draw_texture_rect_region(tex, Rect2((vis.position - region.position) / tpp, vis.size / tpp),
			Rect2((vis.position - Vector2(world_rect.position)) / texel_tiles,
			vis.size / texel_tiles))


func _draw_marker(tile_pos: Vector2, region: Rect2, tpp: int, color: Color, px: int,
		to_border := false) -> void:
	var local := (tile_pos - region.position) / tpp
	if local.x < 0.0 or local.y < 0.0 or local.x >= size.x or local.y >= size.y:
		if not to_border:
			return
		local = _project_to_border(local)
		var edge_origin := (local - Vector2.ONE * px * 0.5).floor()
		edge_origin = edge_origin.clamp(Vector2.ZERO, size - Vector2.ONE * px)
		draw_rect(Rect2(edge_origin, Vector2.ONE * px), color)
		return
	draw_rect(Rect2(local.floor(), Vector2.ONE * px), color)


## Pins never fog out: an in-view pin draws at its spot; an out-of-view one is projected onto the
## widget border along the direction from centre, so it reads as "this way" toward the target.
func _draw_pin(tile_pos: Vector2, region: Rect2, tpp: int) -> void:
	var local := (tile_pos - region.position) / tpp
	if local.x < 0.0 or local.y < 0.0 or local.x >= size.x or local.y >= size.y:
		local = _project_to_border(local)
	var o := (local - Vector2(PIN_PX, PIN_PX) * 0.5).floor()
	o = o.clamp(Vector2.ZERO, size - Vector2(PIN_PX, PIN_PX))   # keep the whole marker on-screen
	draw_rect(Rect2(o, Vector2(PIN_PX, PIN_PX)), COLOR_PIN)


## Scale the centre→point ray until it meets the widget's edge rectangle, giving the border
## crossing in that direction (the off-range pin's indicator position).
func _project_to_border(local: Vector2) -> Vector2:
	var half := size * 0.5
	var d := local - half
	if is_zero_approx(d.x) and is_zero_approx(d.y):
		return half
	var sx := half.x / absf(d.x) if not is_zero_approx(d.x) else INF
	var sy := half.y / absf(d.y) if not is_zero_approx(d.y) else INF
	return half + d * minf(sx, sy)
