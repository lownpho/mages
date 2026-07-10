extends Control
## The strip minimap: draws the shared MapState's discovered-world textures with the player fixed
## at the centre, north-up. The state (fog-of-war discovery, textures, markers) is owned by
## GlobalMap; this widget only renders the active one and steps its own zoom. The widget never
## resizes — the scroll wheel steps tiles-per-pixel (MapState.ZOOM_TILES_PER_PX). Walls render at
## every zoom from a per-level majority-downsampled image, so explored dead ends stay flagged when
## zoomed out. Live enemies show only inside discovered rooms, so nothing leaks through fog of war.

const ENEMIES_MAX_TPP := 4  ## live enemy dots hidden at zooms coarser than this

# Marker colors, all Zughy 32.
const COLOR_UNKNOWN := Palette.BLACK
const COLOR_PLAYER := Palette.WHITE
const COLOR_ENEMY := Palette.RED
const COLOR_BOSS := Palette.YELLOW
const COLOR_FEATURE := Palette.CYAN
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


func _unhandled_input(event: InputEvent) -> void:
	if _state == null:
		return
	if event.is_action_pressed("minimap_zoom_in") and _zoom_idx > 0:
		_zoom_idx -= 1
		queue_redraw()
	elif event.is_action_pressed("minimap_zoom_out") \
			and _zoom_idx < MapState.ZOOM_TILES_PER_PX.size() - 1:
		_zoom_idx += 1
		queue_redraw()


## Left-click a spot on the minimap to drop a pin there; click near an existing pin to clear it.
## The click's widget-local position maps back to a world tile through the same centre/zoom the
## draw uses. (Runs as _gui_input because the widget's mouse_filter stops events at the GUI layer.)
func _gui_input(event: InputEvent) -> void:
	if _state == null or _player == null or not is_instance_valid(_player):
		return
	if event is InputEventMouseButton and event.pressed \
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

	_draw_layer(_state.floor_texture, region, tpp, 1)
	_draw_layer(_state.wall_texture_for(tpp), region, tpp, tpp)

	for m in _state.markers:
		if m["kind"] == MapState.MARKER_BOSS:
			_draw_marker(Vector2(m["tile"]) + Vector2(0.5, 0.5), region, tpp, COLOR_BOSS, 2)
		else:
			_draw_marker(Vector2(m["tile"]) + Vector2(0.5, 0.5), region, tpp, COLOR_FEATURE, 1)
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
func _draw_layer(tex: ImageTexture, region: Rect2, tpp: int, texel_tiles: int) -> void:
	var vis := region.intersection(Rect2(Vector2.ZERO, Vector2(_state.world_tiles)))
	if not vis.has_area():
		return
	draw_texture_rect_region(tex, Rect2((vis.position - region.position) / tpp, vis.size / tpp),
			Rect2(vis.position / texel_tiles, vis.size / texel_tiles))


func _draw_marker(tile_pos: Vector2, region: Rect2, tpp: int, color: Color, px: int) -> void:
	var local := (tile_pos - region.position) / tpp
	if local.x < 0.0 or local.y < 0.0 or local.x >= size.x or local.y >= size.y:
		return
	draw_rect(Rect2(local.floor(), Vector2(px, px)), color)


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
