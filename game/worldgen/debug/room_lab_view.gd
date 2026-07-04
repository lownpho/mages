extends Node2D
## Room Lab canvas: draws a grid of independently-generated rooms to the right of the
## control panel. Same tile-class palette as room_view; P/M toggle the PROTECTED / reachability
## overlays across every cell. Lays out from the window size (content scaling is disabled).

const CLASS_COLORS := {
	RoomBuilder.FLOOR: Color(0.12, 0.12, 0.16),
	RoomBuilder.WALL: Color(0.78, 0.76, 0.68),
	RoomBuilder.BLOCKER: Color(0.47, 0.45, 0.42),
	RoomBuilder.DECOR_FLOOR: Color(0.16, 0.28, 0.18),
}

const CELL_GAP := 10.0
const CELL_TOP := 12.0

var panel_width := 320.0
var show_protected := false
var show_reach := false

var _config: GenConfig = null
var _outputs: Array = []      ## of RoomOutput
var _cols := 1
var _rows := 1


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)


func set_data(config: GenConfig, outputs: Array, cols: int, rows: int) -> void:
	_config = config
	_outputs = outputs
	_cols = maxi(cols, 1)
	_rows = maxi(rows, 1)
	queue_redraw()


func toggle_protected() -> void:
	show_protected = not show_protected
	queue_redraw()


func toggle_reach() -> void:
	show_reach = not show_reach
	queue_redraw()


func _draw() -> void:
	if _config == null or _outputs.is_empty():
		return
	var view := get_viewport_rect().size
	var area_x := panel_width + CELL_GAP
	var area_w := view.x - area_x - CELL_GAP
	var area_h := view.y - CELL_TOP - CELL_GAP
	var cell_w := (area_w - (_cols - 1) * CELL_GAP) / _cols
	var cell_h := (area_h - (_rows - 1) * CELL_GAP) / _rows
	if cell_w <= 4.0 or cell_h <= 4.0:
		return

	for i in _outputs.size():
		var out: RoomOutput = _outputs[i]
		if out == null:
			continue
		var col := i % _cols
		var row := i / _cols
		var cell_pos := Vector2(area_x + col * (cell_w + CELL_GAP), CELL_TOP + row * (cell_h + CELL_GAP))
		_draw_room(out, cell_pos, Vector2(cell_w, cell_h))


func _draw_room(out: RoomOutput, cell_pos: Vector2, cell_size: Vector2) -> void:
	var w := out.width
	var h := out.height
	# Reserve a strip at the bottom of the cell for the label.
	var draw_h := cell_size.y - 16.0
	var ppt := minf(cell_size.x / w, draw_h / h)
	var origin := cell_pos + Vector2((cell_size.x - ppt * w) * 0.5, 0.0)
	var tile := Vector2(ppt, ppt)

	draw_rect(Rect2(origin, Vector2(w, h) * ppt), CLASS_COLORS[RoomBuilder.FLOOR])
	for y in h:
		var r := y * w
		for x in w:
			var c := out.tile_grid[r + x]
			if c != RoomBuilder.FLOOR:
				draw_rect(Rect2(origin + Vector2(x, y) * ppt, tile), CLASS_COLORS[c])
	if show_protected:
		var pc := Color(0.2, 0.9, 1.0, 0.35)
		for y in h:
			var r := y * w
			for x in w:
				if out.protected_map[r + x] == 1:
					draw_rect(Rect2(origin + Vector2(x, y) * ppt, tile), pc)
	if show_reach:
		var rc := Color(0.2, 1.0, 0.3, 0.22)
		for y in h:
			var r := y * w
			for x in w:
				if out.reachability_map[r + x] == 1:
					draw_rect(Rect2(origin + Vector2(x, y) * ppt, tile), rc)
	draw_rect(Rect2(origin, Vector2(w, h) * ppt), Color(1, 1, 1, 0.35), false, 1.0)

	# Spawn markers.
	var col := Color(0.9, 0.2, 0.2)
	for sp in out.spawns:
		if not (sp is Dictionary):
			continue
		var stile: Vector2i = sp.get("tile", Vector2i.ZERO)
		draw_circle(origin + (Vector2(stile) + Vector2(0.5, 0.5)) * ppt, maxf(2.0, ppt * 0.6), col)

	var label := "%s  %dx%d  attempt %d  %d spawns" % [
		out.type_id, w, h, out.attempt_used, out.spawns.size()]
	draw_string(ThemeDB.fallback_font, cell_pos + Vector2(2, cell_size.y - 3), label,
			HORIZONTAL_ALIGNMENT_LEFT, cell_size.x, 12, Color(0.82, 0.85, 0.9))
