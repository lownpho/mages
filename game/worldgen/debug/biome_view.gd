extends Node2D
## Debug view 2 (spec §12 tooling 2): the selected biome's slot grid with rooms as
## outlined rects (merged rooms render larger), passages on shared edges (tree = white, loop =
## yellow, external contract door = red; DOOR = short tick at its true offset, OPEN = the whole
## shared segment highlighted), a short type tag per room, and unique-scope rooms outlined in a
## distinct colour. A small world overview sits in the corner with the current selection ringed.

const TOP := 56.0
const MARGIN := 24.0
const OVERVIEW_CELL := 22.0

var _spec: WorldSpec = null
var _config: GenConfig = null
var _graph: BiomeGraph = null
var _selected := Vector2i.ZERO
var _selected_room := -1


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)


func set_data(spec: WorldSpec, config: GenConfig, graph: BiomeGraph, selected: Vector2i,
		selected_room := -1) -> void:
	_spec = spec
	_config = config
	_graph = graph
	_selected = selected
	_selected_room = selected_room
	queue_redraw()


## Main-grid layout shared by _draw and hit-testing: [origin: Vector2, slot_px: float].
func _layout() -> Array:
	var view := get_viewport_rect().size
	var s := _config.biome_slots
	var main_top: float = TOP + _spec.grid_h * OVERVIEW_CELL + 16.0
	var slot_px := minf((view.x - 2.0 * MARGIN) / s, (view.y - main_top - MARGIN) / s)
	return [Vector2((view.x - slot_px * s) * 0.5, main_top), slot_px]


## Index (into _graph.rooms) of the room under a screen position, or -1 outside the main grid.
func room_at_screen_pos(pos: Vector2) -> int:
	if _graph == null:
		return -1
	var lay := _layout()
	var origin: Vector2 = lay[0]
	var slot_px: float = lay[1]
	var s := _config.biome_slots
	var rel := (pos - origin) / slot_px
	var lx := int(floor(rel.x))
	var ly := int(floor(rel.y))
	if lx < 0 or ly < 0 or lx >= s or ly >= s:
		return -1
	return _graph.slot_to_room[ly * s + lx]


## Top-left corner of the overview grid in screen space.
func _overview_origin() -> Vector2:
	var view := get_viewport_rect().size
	return Vector2(view.x - MARGIN - _spec.grid_w * OVERVIEW_CELL, TOP)


## Biome cell under a screen position (for click-to-select), or (-1,-1) if outside the overview.
func cell_at_screen_pos(pos: Vector2) -> Vector2i:
	if _spec == null:
		return Vector2i(-1, -1)
	var o := _overview_origin()
	var rel := (pos - o) / OVERVIEW_CELL
	var cx := int(floor(rel.x))
	var cy := int(floor(rel.y))
	if cx < 0 or cy < 0 or cx >= _spec.grid_w or cy >= _spec.grid_h:
		return Vector2i(-1, -1)
	return Vector2i(cx, cy)


func _draw() -> void:
	if _graph == null:
		return
	var view := get_viewport_rect().size
	var s := _config.biome_slots
	var t := float(_config.room_slot_tiles)
	var font := ThemeDB.fallback_font

	# Main 9x9 slot grid, below the overview band.
	var lay := _layout()
	var origin: Vector2 = lay[0]
	var slot_px: float = lay[1]
	var ppt := slot_px / t   # pixels per tile

	# Faint slot lattice.
	for i in s + 1:
		var gx := origin.x + i * slot_px
		var gy := origin.y + i * slot_px
		draw_line(Vector2(gx, origin.y), Vector2(gx, origin.y + s * slot_px), Color(1, 1, 1, 0.08))
		draw_line(Vector2(origin.x, gy), Vector2(origin.x + s * slot_px, gy), Color(1, 1, 1, 0.08))

	var bc := _graph.biome_coord
	for ui in _graph.rooms.size():
		var u: RoomSpec = _graph.rooms[ui]
		var lt := Vector2(u.origin_slot - bc * s)
		var rect := Rect2(origin + lt * slot_px, Vector2(u.size_slots) * slot_px)
		if ui == _selected_room:
			draw_rect(rect.grow(-1.0), Color(1, 1, 1, 0.15))
		var rt := _config.room_type_by_id(u.type_id)
		var outline := Color(0.6, 0.6, 0.7)
		if rt != null and rt.unique_scope == RoomTypeDef.UniqueScope.WORLD:
			outline = Color.GOLD
		elif rt != null and rt.unique_scope == RoomTypeDef.UniqueScope.BIOME:
			outline = Color.CYAN
		draw_rect(rect.grow(-2.0), outline, false, 2.0)
		var tag := String(u.type_id).substr(0, 3).to_upper()
		draw_string(font, rect.position + Vector2(6, 18), tag,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.9, 0.95))
		for p in u.passages:
			_draw_passage(lt, u.size_slots, p, origin, slot_px, ppt)

	_draw_overview()

	draw_string(font, Vector2(MARGIN, view.y - 12), "biome %s  [%s]  rooms:%d   arrows/click select"
			% [bc, _graph.rooms[0].biome_id, _graph.rooms.size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.85, 0.9))


func _draw_passage(lt: Vector2, size: Vector2i, p, origin: Vector2, slot_px: float, ppt: float) -> void:
	var col := Color.RED if p.external else (Color.WHITE if p.from_tree else Color.YELLOW)
	var a: Vector2
	var b: Vector2
	match p.side:
		WorldSpec.SIDE_NORTH, WorldSpec.SIDE_SOUTH:
			var edge_y: float = origin.y + (lt.y + (size.y if p.side == WorldSpec.SIDE_SOUTH else 0)) * slot_px
			var off: float = p.offset_tiles
			var wid: float = p.width_tiles
			var x0: float = origin.x + lt.x * slot_px + off * ppt
			a = Vector2(x0, edge_y)
			b = Vector2(x0 + wid * ppt, edge_y)
		_:
			var edge_x: float = origin.x + (lt.x + (size.x if p.side == WorldSpec.SIDE_EAST else 0)) * slot_px
			var off: float = p.offset_tiles
			var wid: float = p.width_tiles
			var y0: float = origin.y + lt.y * slot_px + off * ppt
			a = Vector2(edge_x, y0)
			b = Vector2(edge_x, y0 + wid * ppt)
	draw_line(a, b, col, 3.0)


func _draw_overview() -> void:
	var o := _overview_origin()
	var font := ThemeDB.fallback_font
	for y in _spec.grid_h:
		for x in _spec.grid_w:
			var bid := _spec.biome_at(Vector2i(x, y))
			var biome := _config.biome_by_id(bid)
			var rect := Rect2(o + Vector2(x, y) * OVERVIEW_CELL, Vector2(OVERVIEW_CELL, OVERVIEW_CELL))
			draw_rect(rect, biome.display_color if biome else Color.MAGENTA)
			draw_rect(rect, Color.BLACK, false, 1.0)
			if Vector2i(x, y) == _selected:
				draw_rect(rect.grow(-1.0), Color.WHITE, false, 2.0)
	draw_string(font, o + Vector2(0, -4), "world", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.85))
