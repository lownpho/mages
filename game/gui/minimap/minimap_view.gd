extends Control
## The strip minimap: draws MapState's discovered-world textures with the player fixed at
## the centre, north-up. The widget never resizes — the scroll wheel steps tiles-per-pixel
## (ZOOM_TILES_PER_PX). Walls render at every zoom from a per-level majority-downsampled
## image, so explored dead ends stay flagged when zoomed out. Live enemies show only inside
## discovered rooms, so nothing leaks through fog of war.

const ZOOM_TILES_PER_PX: Array[int] = [1, 2, 4, 8, 16, 32]
const ENEMIES_MAX_TPP := 4  ## live enemy dots hidden at zooms coarser than this

# Marker colors, all Zughy 32.
const COLOR_UNKNOWN := Palette.BLACK
const COLOR_PLAYER := Palette.WHITE
const COLOR_ENEMY := Palette.RED
const COLOR_BOSS := Palette.YELLOW
const COLOR_FEATURE := Palette.CYAN

var _state: MapState = null
var _player: Node2D = null
var _zoom_idx := 0
var _last_tile := Vector2i(-1, -1)


func _ready() -> void:
	GlobalEvent.world_ready.connect(_on_world_ready)
	set_process(false)


func _on_world_ready(streamer: WorldStreamer) -> void:
	_state = MapState.new()
	_state.setup(streamer, ZOOM_TILES_PER_PX)
	_player = get_tree().get_first_node_in_group("player")
	_last_tile = Vector2i(-1, -1)
	set_process(true)
	queue_redraw()


func _process(_dt: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var tile := Vector2i((_player.global_position / GameConstants.PX_PER_TILE).floor())
	if tile != _last_tile:
		_last_tile = tile
		_state.discover_at(tile)
	queue_redraw()   # enemies move even when the player doesn't


func _unhandled_input(event: InputEvent) -> void:
	if _state == null:
		return
	if event.is_action_pressed("minimap_zoom_in") and _zoom_idx > 0:
		_zoom_idx -= 1
		queue_redraw()
	elif event.is_action_pressed("minimap_zoom_out") and _zoom_idx < ZOOM_TILES_PER_PX.size() - 1:
		_zoom_idx += 1
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_UNKNOWN)
	if _state == null or _player == null or not is_instance_valid(_player):
		return
	var tpp := ZOOM_TILES_PER_PX[_zoom_idx]
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
