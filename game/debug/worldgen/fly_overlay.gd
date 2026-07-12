extends Node2D
## Fly-view overlays, drawn in WORLD space over the streamed tiles (view 4). All lookups are
## read-through: rooms come from the same graph cache the streamer uses, so drawing never
## generates anything the streamer wouldn't. Line widths divide by camera zoom so they stay
## one screen-width thick at any zoom. Toggles (wired by worldgen_debug):
##   show_bounds — room rectangles + "type tier/depth" tags
##   show_grid   — streaming-chunk lattice
##   show_heat   — difficulty-tier heatmap wash over each room (green 0 → red 3)
##   show_borders — biome region borders

var show_bounds := false
var show_grid := false
var show_heat := false
var show_borders := true

var config: GenConfig = null
var world_spec: WorldSpec = null
var room_graphs: RoomGraph = null    ## shared cache, injected by worldgen_debug

const TIER_COLORS := [Color(0.2, 0.9, 0.3, 0.18), Color(0.9, 0.9, 0.2, 0.18),
		Color(1.0, 0.6, 0.15, 0.20), Color(1.0, 0.2, 0.15, 0.22)]


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func set_data(spec: WorldSpec, cfg: GenConfig, graphs: RoomGraph) -> void:
	world_spec = spec
	config = cfg
	room_graphs = graphs
	queue_redraw()


## World-space rect currently on screen (from the active camera).
func _visible_world_rect() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2()
	var half := get_viewport_rect().size * 0.5 / cam.zoom
	return Rect2(cam.get_screen_center_position() - half, half * 2.0)


func _draw() -> void:
	if world_spec == null or config == null or room_graphs == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var rect := _visible_world_rect()
	var lw := 2.0 / cam.zoom.x
	var px := GameConstants.PX_PER_TILE

	if show_grid:
		_draw_chunk_grid(rect, lw)
	if show_bounds or show_heat:
		_draw_rooms(rect, lw, cam.zoom.x)
	if show_borders:
		_draw_biome_borders(rect, lw)

	# Sealed-world outline so the world edge is obvious when zoomed way out.
	var wpx := Vector2(world_spec.grid_w, world_spec.grid_h) * config.biome_slots \
			* config.room_slot_tiles * px
	draw_rect(Rect2(Vector2.ZERO, wpx), Color(1, 1, 1, 0.5), false, lw)


func _draw_chunk_grid(rect: Rect2, lw: float) -> void:
	var cpx := config.chunk_tiles * GameConstants.PX_PER_TILE
	var col := Color(0.4, 0.7, 1.0, 0.35)
	var x0 := floori(rect.position.x / cpx)
	var x1 := ceili(rect.end.x / cpx)
	var y0 := floori(rect.position.y / cpx)
	var y1 := ceili(rect.end.y / cpx)
	if (x1 - x0) > 200 or (y1 - y0) > 200:
		return   # zoomed out too far for a useful lattice
	for gx in range(x0, x1 + 1):
		draw_line(Vector2(gx * cpx, rect.position.y), Vector2(gx * cpx, rect.end.y), col, lw)
	for gy in range(y0, y1 + 1):
		draw_line(Vector2(rect.position.x, gy * cpx), Vector2(rect.end.x, gy * cpx), col, lw)


## Rooms overlapping the visible rect, deduped by origin slot via the shared graph cache.
func _rooms_in_rect(rect: Rect2) -> Array:
	var out: Array = []
	var spx := config.room_slot_tiles * GameConstants.PX_PER_TILE
	var s0 := Vector2i(floori(rect.position.x / spx), floori(rect.position.y / spx))
	var s1 := Vector2i(ceili(rect.end.x / spx), ceili(rect.end.y / spx))
	var max_slots := Vector2i(world_spec.grid_w, world_spec.grid_h) * config.biome_slots
	var done: Dictionary = {}
	for sy in range(maxi(s0.y, 0), mini(s1.y, max_slots.y - 1) + 1):
		for sx in range(maxi(s0.x, 0), mini(s1.x, max_slots.x - 1) + 1):
			var slot := Vector2i(sx, sy)
			var bid := world_spec.biome_at_slot(slot)
			if bid == &"":
				continue
			var graph := room_graphs.get_biome_graph(world_spec, bid, config)
			var spec := graph.room_at(slot - graph.origin_slot)
			if spec == null or done.has(spec.origin_slot):
				continue
			done[spec.origin_slot] = true
			out.append(spec)
	return out


func _draw_rooms(rect: Rect2, lw: float, zoom: float) -> void:
	var spx := config.room_slot_tiles * GameConstants.PX_PER_TILE
	var font := ThemeDB.fallback_font
	for spec in _rooms_in_rect(rect):
		var rrect := Rect2(Vector2(spec.origin_slot) * spx, Vector2(spec.size_slots) * spx)
		if show_heat:
			draw_rect(rrect, TIER_COLORS[spec.tier()])
		if show_bounds:
			draw_rect(rrect, Color(1, 1, 1, 0.55), false, lw)
			# Tag stays readable at any zoom: font size is screen-fixed, drawn scaled.
			var fs := 13.0 / zoom
			draw_string(font, rrect.position + Vector2(4.0 / zoom, fs + 2.0 / zoom),
					"%s  t%d d%d" % [spec.type_id, spec.tier(), spec.depth],
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), Color(1, 1, 0.6, 0.9))


func _draw_biome_borders(rect: Rect2, lw: float) -> void:
	var bpx := config.biome_slots * config.room_slot_tiles * GameConstants.PX_PER_TILE
	var col := Color(1.0, 0.4, 0.9, 0.6)
	var c0 := Vector2i(floori(rect.position.x / bpx), floori(rect.position.y / bpx))
	var c1 := Vector2i(ceili(rect.end.x / bpx), ceili(rect.end.y / bpx))
	for cy in range(maxi(c0.y, 0), mini(c1.y, world_spec.grid_h - 1) + 1):
		for cx in range(maxi(c0.x, 0), mini(c1.x, world_spec.grid_w - 1) + 1):
			var cell := Vector2i(cx, cy)
			var here := world_spec.biome_at(cell)
			var east := world_spec.biome_at(cell + Vector2i(1, 0))
			if here != east:
				draw_line(Vector2((cx + 1) * bpx, cy * bpx), Vector2((cx + 1) * bpx, (cy + 1) * bpx),
						col, lw * 1.5)
			var south := world_spec.biome_at(cell + Vector2i(0, 1))
			if here != south:
				draw_line(Vector2(cx * bpx, (cy + 1) * bpx), Vector2((cx + 1) * bpx, (cy + 1) * bpx),
						col, lw * 1.5)
