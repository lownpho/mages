extends Node2D
## Debug view 3: one room's logical tile grid. FLOOR dark, WALL
## light, BLOCKER mid, DECOR_FLOOR tinted. P toggles the PROTECTED overlay (translucent cyan),
## M the reachability overlay (translucent green). Left/right arrows cycle rooms (handled by
## the root). Lays out from the window size (viewport is 320×180-stretched otherwise).

const TOP := 56.0
const MARGIN := 24.0

const CLASS_COLORS := {
	RoomBuilder.FLOOR: Color(0.12, 0.12, 0.16),
	RoomBuilder.WALL: Color(0.78, 0.76, 0.68),
	RoomBuilder.BLOCKER: Color(0.47, 0.45, 0.42),
	RoomBuilder.DECOR_FLOOR: Color(0.16, 0.28, 0.18),
}

var show_protected := false
var show_reach := false

var _config: GenConfig = null
var _out: RoomOutput = null
var _room_index: int = 0
var _room_count: int = 0


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)


func set_data(config: GenConfig, out: RoomOutput, room_index: int, room_count: int) -> void:
	_config = config
	_out = out
	_room_index = room_index
	_room_count = room_count
	queue_redraw()


func toggle_protected() -> void:
	show_protected = not show_protected
	queue_redraw()


func toggle_reach() -> void:
	show_reach = not show_reach
	queue_redraw()


func _draw() -> void:
	if _out == null:
		return
	var view := get_viewport_rect().size
	var w := _out.width
	var h := _out.height
	var ppt := minf((view.x - 2.0 * MARGIN) / w, (view.y - TOP - MARGIN - 28.0) / h)
	var origin := Vector2((view.x - ppt * w) * 0.5, TOP)

	# Floor as one background rect; only non-floor tiles drawn individually.
	draw_rect(Rect2(origin, Vector2(w, h) * ppt), CLASS_COLORS[RoomBuilder.FLOOR])
	var tile := Vector2(ppt, ppt)
	for y in h:
		var row := y * w
		for x in w:
			var c := _out.tile_grid[row + x]
			if c != RoomBuilder.FLOOR:
				draw_rect(Rect2(origin + Vector2(x, y) * ppt, tile), CLASS_COLORS[c])
	if show_protected:
		var pc := Color(0.2, 0.9, 1.0, 0.35)
		for y in h:
			var row := y * w
			for x in w:
				if _out.protected_map[row + x] == 1:
					draw_rect(Rect2(origin + Vector2(x, y) * ppt, tile), pc)
	if show_reach:
		var rc := Color(0.2, 1.0, 0.3, 0.25)
		for y in h:
			var row := y * w
			for x in w:
				if _out.reachability_map[row + x] == 1:
					draw_rect(Rect2(origin + Vector2(x, y) * ppt, tile), rc)
	draw_rect(Rect2(origin, Vector2(w, h) * ppt), Color(1, 1, 1, 0.4), false, 1.0)

	# Spawn markers: enemies red, id as tiny text.
	var font := ThemeDB.fallback_font
	var col := Color(0.9, 0.2, 0.2)
	for sp in _out.spawns:
		if not (sp is Dictionary):
			continue
		var stile: Vector2i = sp.get("tile", Vector2i.ZERO)
		var pos := origin + (Vector2(stile) + Vector2(0.5, 0.5)) * ppt
		draw_circle(pos, maxf(2.5, ppt), col)
		var sid: StringName = sp.get("enemy_id", &"?")
		draw_string(font, pos + Vector2(4, -3), String(sid),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)

	var status := "room %d/%d  %s  [%s]  %dx%d slots  %dx%d tiles   [P] protected:%s  [M] reach:%s  [←/→] cycle" % [
		_room_index + 1, _room_count, _out.origin_slot, _out.type_id,
		_out.width / _config.room_slot_tiles, _out.height / _config.room_slot_tiles,
		w, h, "on" if show_protected else "off", "on" if show_reach else "off"]
	draw_string(ThemeDB.fallback_font, Vector2(MARGIN, view.y - 10), status,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.88, 0.92))
