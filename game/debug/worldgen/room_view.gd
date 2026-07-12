extends Node2D
## Debug view 3: ONE real room of the current world, exactly as the streamer would build it
## (RoomBuilder.build on the selected RoomSpec — not a synthetic lab room). Tile classes in
## the shared palette, passages on the borders, L4 spawn points as numbered markers with an
## enemy-id list alongside, and a header with the room's identity (type, tier, depth, size).
## P toggles the PROTECTED mask, M the reachability map — same keys as the room lab.

const CLASS_COLORS := {
	RoomBuilder.FLOOR: Color(0.12, 0.12, 0.16),
	RoomBuilder.WALL: Color(0.78, 0.76, 0.68),
	RoomBuilder.BLOCKER: Color(0.47, 0.45, 0.42),
	RoomBuilder.DECOR_FLOOR: Color(0.16, 0.28, 0.18),
}
const TOP := 56.0
const MARGIN := 24.0
const SIDE_W := 220.0   ## right strip for the spawn list

var show_protected := false
var show_reach := false

var _spec: RoomSpec = null
var _out: RoomOutput = null
var _tier := 0


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)


func set_data(spec: RoomSpec, out: RoomOutput) -> void:
	_spec = spec
	_out = out
	_tier = spec.tier() if spec != null else 0
	queue_redraw()


func toggle_protected() -> void:
	show_protected = not show_protected
	queue_redraw()


func toggle_reach() -> void:
	show_reach = not show_reach
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	if _out == null:
		draw_string(font, Vector2(MARGIN, TOP + 20), "no room selected — pick one in the biome view (2)",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.85, 0.9))
		return
	var w := _out.width
	var h := _out.height
	var ppt := minf((view.x - 2.0 * MARGIN - SIDE_W) / w, (view.y - TOP - MARGIN - 20.0) / h)
	var origin := Vector2(MARGIN, TOP + 20.0)
	var tile := Vector2(ppt, ppt)

	# Header.
	draw_string(font, Vector2(MARGIN, TOP + 8),
			"%s  @%s  %dx%d tiles  tier %d  depth %d/%d  %d spawns   [P] protected  [M] reach" % [
			_spec.type_id, _spec.origin_slot, w, h, _tier, _spec.depth, _spec.biome_max_depth,
			_out.spawns.size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.92, 1.0))

	# Tiles.
	draw_rect(Rect2(origin, Vector2(w, h) * ppt), CLASS_COLORS[RoomBuilder.FLOOR])
	for y in h:
		var r := y * w
		for x in w:
			var c := _out.tile_grid[r + x]
			if c != RoomBuilder.FLOOR:
				draw_rect(Rect2(origin + Vector2(x, y) * ppt, tile), CLASS_COLORS[c])
	if show_protected:
		var pc := Color(0.2, 0.9, 1.0, 0.35)
		for y in h:
			var r := y * w
			for x in w:
				if _out.protected_map[r + x] == 1:
					draw_rect(Rect2(origin + Vector2(x, y) * ppt, tile), pc)
	if show_reach:
		var rc := Color(0.2, 1.0, 0.3, 0.22)
		for y in h:
			var r := y * w
			for x in w:
				if _out.reachability_map[r + x] == 1:
					draw_rect(Rect2(origin + Vector2(x, y) * ppt, tile), rc)
	draw_rect(Rect2(origin, Vector2(w, h) * ppt), Color(1, 1, 1, 0.4), false, 1.0)

	# Passages along the borders (red = external contract crossing, white = internal).
	for p in _spec.passages:
		var col := Color.RED if p.external else Color.WHITE
		var a: Vector2
		var b: Vector2
		match p.side:
			WorldSpec.SIDE_NORTH, WorldSpec.SIDE_SOUTH:
				var edge_y: float = origin.y + (h if p.side == WorldSpec.SIDE_SOUTH else 0) * ppt
				a = Vector2(origin.x + p.offset_tiles * ppt, edge_y)
				b = a + Vector2(p.width_tiles * ppt, 0)
			_:
				var edge_x: float = origin.x + (w if p.side == WorldSpec.SIDE_EAST else 0) * ppt
				a = Vector2(edge_x, origin.y + p.offset_tiles * ppt)
				b = a + Vector2(0, p.width_tiles * ppt)
		draw_line(a, b, col, 4.0)

	# Spawns: numbered markers + the id list on the right strip.
	var list_x := view.x - MARGIN - SIDE_W
	draw_string(font, Vector2(list_x, origin.y), "spawns", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(0.9, 0.92, 1.0))
	var line_y := origin.y + 18.0
	for i in _out.spawns.size():
		var sp = _out.spawns[i]
		if not (sp is Dictionary):
			continue
		var stile: Vector2i = sp.get("tile", Vector2i.ZERO)
		var pos := origin + (Vector2(stile) + Vector2(0.5, 0.5)) * ppt
		var label: String
		if sp.has("feature"):
			draw_circle(pos, maxf(3.0, ppt * 0.6), Color.GOLD)
			label = "feature"
		else:
			draw_circle(pos, maxf(3.0, ppt * 0.6), Color(0.9, 0.2, 0.2))
			label = String(sp.get("enemy_id", &"?"))
		draw_string(font, pos + Vector2(4, -4), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color.WHITE)
		draw_string(font, Vector2(list_x, line_y), "%2d  %s  @%s" % [i, label, stile],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.85, 0.9))
		line_y += 15.0
