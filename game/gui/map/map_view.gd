extends Control
## The full-screen map: renders the whole active MapState — the same discovered-world textures,
## markers and pins the strip minimap uses (via GlobalMap) — but framed to show everything at once,
## with wheel-zoom (around the cursor), drag-pan, and click-to-pin. Opened from the pin button on
## the HUD strip; Esc / clicking outside closes it (ui.gd, same as the bestiary). Re-fits to the
## discovered world each time it opens, so it always frames what the player has seen so far.
##
## When dungeon floors arrive this becomes the paged "book": one MapState per space, this view
## renders GlobalMap's active one and page controls swap spaces. Today there is a single space.

const COLOR_BG := Palette.BLACK
const COLOR_PLAYER := Palette.WHITE
const COLOR_ENEMY := Palette.RED
const COLOR_BOSS := Palette.YELLOW
const COLOR_FEATURE := Palette.CYAN
const COLOR_PIN := Palette.ORANGE

const PIN_PX := 3
const MARKER_PX := 2
const DRAG_THRESHOLD := 3.0  ## px of motion that turns a click into a pan (so it won't drop a pin)

## Discrete zoom steps in tiles-per-pixel, most-zoomed-out first. Every value is an integer or a
## unit fraction, so the world-tile → screen-pixel scale is always exact (N tiles per pixel, or N
## pixels per tile) — the map stays pixel-perfect at every step, like the rest of the pixel-art UI.
## Wheel steps through these; there is no continuous zoom. Walls downsample on the >1 integer
## levels (see MapState.ZOOM_TILES_PER_PX).
const ZOOM_LADDER: Array[float] = [16.0, 8.0, 4.0, 2.0, 1.0, 0.5, 0.25]

var _state: MapState = null
var _player: Node2D = null
var _cam := Vector2.ZERO      ## world tile at the view centre (kept snapped to the pixel grid)
var _zoom_idx := 4            ## index into ZOOM_LADDER (default 1.0 tile/px)
var _tpp := 1.0               ## tiles per pixel = ZOOM_LADDER[_zoom_idx]
var _fitted := false
var _dragging := false
var _drag_moved := false
var _press_pos := Vector2.ZERO


func _ready() -> void:
	GlobalMap.map_changed.connect(_on_map_changed)
	GlobalMap.pins_changed.connect(queue_redraw)
	%CloseButton.pressed.connect(_close)
	if GlobalMap.active != null:
		_on_map_changed()
	set_process(false)


## Close the whole panel (the themed PanelContainer this view lives inside). Hiding it fires
## NOTIFICATION_VISIBILITY_CHANGED here, which stops our per-frame redraw.
func _close() -> void:
	var p: Node = get_parent()
	while p != null and not (p is PanelContainer):
		p = p.get_parent()
	if p != null:
		p.hide()


func _on_map_changed() -> void:
	_state = GlobalMap.active
	_player = get_tree().get_first_node_in_group("player")
	_fitted = false
	set_process(_state != null and is_visible_in_tree())
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		var vis := is_visible_in_tree()
		set_process(vis and _state != null)
		_fitted = false   # re-frame the whole discovered world on each open
		queue_redraw()


func _process(_dt: float) -> void:
	queue_redraw()   # player and enemies move while the map is open


const FIT_PAD_TILES := 8   ## breathing room (world tiles) around the discovered area when framing

## Frame the discovered area into the widget — so the map fills with what the player has explored
## and grows as they do, rather than showing a speck lost in the mostly-undiscovered world. Falls
## back to the whole world before anything is discovered. Lazy (called from _draw) so `size` is
## already laid out.
func _fit() -> void:
	if _state == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var b := _state.discovered_bounds()
	var area := Vector2(b.size) + Vector2(FIT_PAD_TILES, FIT_PAD_TILES) * 2.0
	var center := Vector2(b.position) + Vector2(b.size) * 0.5
	var has_bounds := b.size.x > 0 and b.size.y > 0
	if not has_bounds:   # nothing discovered yet: show the whole world, but keep retrying
		area = Vector2(_state.world_tiles)
		center = area * 0.5
	# Pick the most zoomed-in ladder step that still fits the area (the coarsest is the fallback).
	var need := maxf(area.x / size.x, area.y / size.y)
	_zoom_idx = 0
	for i in ZOOM_LADDER.size():
		if ZOOM_LADDER[i] >= need:
			_zoom_idx = i
	_tpp = ZOOM_LADDER[_zoom_idx]
	_cam = center
	_snap_cam()
	_fitted = has_bounds   # a whole-world fallback isn't final — re-fit once something is found


## Keep the view origin on whole pixels: one screen pixel spans _tpp tiles, so quantising _cam to
## a multiple of _tpp aligns every tile blit to the pixel grid (no sub-pixel texture smear).
func _snap_cam() -> void:
	_cam = (_cam / _tpp).round() * _tpp


func _gui_input(event: InputEvent) -> void:
	if _state == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom(event.position, 1)    # wheel up → zoom in
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom(event.position, -1)   # wheel down → zoom out
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_moved = false
				_press_pos = event.position
			else:
				_dragging = false
				if not _drag_moved:   # a tap, not a drag → drop/remove a pin
					GlobalMap.toggle_pin(Vector2i(_screen_to_world(event.position).floor()),
							maxi(1, int(ceil(_tpp * 3))))
		# Consume every mouse button over the map — zoom, pan and pin alike. Otherwise the wheel
		# events leak to ui.gd's _unhandled_input, which reads any press as an outside click and
		# closes the panel.
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		if event.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_drag_moved = true
		_cam -= event.relative * _tpp
		_snap_cam()
		queue_redraw()
		accept_event()


## Step one ladder level (dir +1 = in, -1 = out), keeping the world point under the cursor pinned
## in place so zoom feels anchored to where you're looking. Snapped, so it stays pixel-perfect.
func _zoom(local: Vector2, dir: int) -> void:
	var ni := clampi(_zoom_idx + dir, 0, ZOOM_LADDER.size() - 1)
	if ni == _zoom_idx:
		return
	var before := _screen_to_world(local)
	_zoom_idx = ni
	_tpp = ZOOM_LADDER[_zoom_idx]
	_cam += before - _screen_to_world(local)
	_snap_cam()
	queue_redraw()


func _screen_to_world(local: Vector2) -> Vector2:
	return _cam + (local - size * 0.5) * _tpp


func _world_to_screen(world: Vector2) -> Vector2:
	return (world - _cam) / _tpp + size * 0.5


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
	if _state == null:
		return
	if not _fitted:
		_fit()
	var region := Rect2(_cam - size * _tpp * 0.5, size * _tpp)

	_draw_layer(_state.floor_texture, region, 1)
	var wl := _nearest_wall_level(_tpp)
	_draw_layer(_state.wall_texture_for(wl), region, wl)

	for m in _state.markers:
		var c: Color = COLOR_BOSS if m["kind"] == MapState.MARKER_BOSS else COLOR_FEATURE
		_dot(Vector2(m["tile"]) + Vector2(0.5, 0.5), MARKER_PX, c, false)
	for e in get_tree().get_nodes_in_group("enemies"):
		var et: Vector2 = e.global_position / GameConstants.PX_PER_TILE
		if _state.is_tile_discovered(Vector2i(et.floor())):
			_dot(et, 1, COLOR_ENEMY, false)
	for p in _state.pins:
		_dot(Vector2(p) + Vector2(0.5, 0.5), PIN_PX, COLOR_PIN, true)   # pins clamp to the border
	if _player != null and is_instance_valid(_player):
		_dot(_player.global_position / GameConstants.PX_PER_TILE, MARKER_PX, COLOR_PLAYER, false)


## Blit the world-texture slice visible through `region` (in tiles), clamped to the world so
## out-of-bounds sampling never smears edges. `texel_tiles` is how many world tiles one texel of
## `tex` spans (1 for the full-res floor, the wall level for a downsampled wall image).
func _draw_layer(tex: ImageTexture, region: Rect2, texel_tiles: int) -> void:
	if tex == null:
		return
	var vis := region.intersection(Rect2(Vector2.ZERO, Vector2(_state.world_tiles)))
	if not vis.has_area():
		return
	# Floor the on-screen destination onto whole pixels (an odd panel size puts the view centre on
	# a half-pixel); the scale is already exact from the ladder, so this keeps the blit crisp.
	var dst := Rect2(((vis.position - region.position) / _tpp).floor(), (vis.size / _tpp).ceil())
	draw_texture_rect_region(tex, dst, Rect2(vis.position / texel_tiles, vis.size / texel_tiles))


## Largest authored wall zoom level not finer than the current zoom, so walls stay legible as they
## downsample. Falls back to full-res (1) when zoomed in past the first level.
func _nearest_wall_level(tpp: float) -> int:
	var lvl := 1
	for l in MapState.ZOOM_TILES_PER_PX:
		if float(l) <= tpp:
			lvl = l
	return lvl


## Draw a marker at a world-tile position. Off-view markers are dropped unless `clamp` is set, in
## which case they project onto the widget border along their direction (used for pins).
func _dot(world: Vector2, px: int, color: Color, clamp: bool) -> void:
	var s := _world_to_screen(world)
	if s.x < 0.0 or s.y < 0.0 or s.x >= size.x or s.y >= size.y:
		if not clamp:
			return
		s = _project_to_border(s)
	var o := (s - Vector2(px, px) * 0.5).floor()
	o = o.clamp(Vector2.ZERO, size - Vector2(px, px))
	draw_rect(Rect2(o, Vector2(px, px)), color)


func _project_to_border(s: Vector2) -> Vector2:
	var half := size * 0.5
	var d := s - half
	if is_zero_approx(d.x) and is_zero_approx(d.y):
		return half
	var sx := half.x / absf(d.x) if not is_zero_approx(d.x) else INF
	var sy := half.y / absf(d.y) if not is_zero_approx(d.y) else INF
	return half + d * minf(sx, sy)
