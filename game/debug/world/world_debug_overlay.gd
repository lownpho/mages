class_name WorldDebugOverlay
extends Node2D
## Read-only World-space drawing over the streamed tiles. It consumes the complete graph and never
## asks streaming to build a tile, so opening the tool cannot perturb generation order.

const ROLE_COLORS := [Color(0.65, 0.72, 0.82), Color(0.35, 0.8, 1.0), Color(0.35, 0.9, 0.55),
		Color.WHITE, Color(1.0, 0.25, 0.2), Color(1.0, 0.55, 0.15), Color(0.85, 0.35, 1.0)]
const PASSAGE_COLORS := [Color.WHITE, Color(0.65, 0.7, 0.78), Color.YELLOW,
		Color.CYAN, Color(1.0, 0.45, 0.2), Color(1.0, 0.3, 0.75)]

var graph: WorldGraph
var overlays: Dictionary = {}
var entered_rooms: Dictionary[String, bool] = {}


func set_data(world_graph: WorldGraph, enabled: Dictionary) -> void:
	graph = world_graph
	overlays = enabled
	queue_redraw()


func set_entered_rooms(entered: Dictionary[String, bool]) -> void:
	entered_rooms = entered
	queue_redraw()


func _process(_delta: float) -> void:
	if visible and graph != null:
		queue_redraw()


func _draw() -> void:
	if graph == null:
		return
	var px := float(GameConstants.PX_PER_TILE)
	var camera := get_viewport().get_camera_2d()
	var width := 1.5 / camera.zoom.x if camera != null else 1.5
	if overlays.get("zones", false) or overlays.get("challenge", false):
		for room in graph.room_list:
			var color := Color.TRANSPARENT
			if overlays.get("challenge", false):
				var high := maxi(1, graph.plan.content.biomes[room.plan.biome].exit_challenge)
				color = Color.from_hsv(0.33 - 0.33 * room.plan.challenge / high, 0.8, 0.85, 0.16)
			elif overlays.get("zones", false):
				color = _key_color("%s/%s" % [room.plan.biome, room.plan.zone], 0.14)
			draw_colored_polygon(_scaled(room.polygon, px), color)
	if overlays.get("discovery", false):
		for room in graph.room_list:
			var color := Color(0.3, 0.85, 1.0, 0.18) if entered_rooms.has(room.key()) else Color(0.02, 0.02, 0.04, 0.24)
			draw_colored_polygon(_scaled(room.polygon, px), color)
	if overlays.get("macro_grid", false):
		for coord in graph.plan.cells:
			draw_rect(Rect2(Vector2(coord * WorldPlan.CELL) * px, Vector2.ONE * WorldPlan.CELL * px),
					Color(0.45, 0.75, 1.0, 0.55), false, width)
		var folded := PackedVector2Array()
		for coord in graph.plan.path:
			folded.append((Vector2(coord * WorldPlan.CELL) + Vector2.ONE * WorldPlan.CELL * 0.5) * px)
		if folded.size() > 1:
			draw_polyline(folded, Color(0.45, 0.75, 1.0, 0.8), width * 2.0)
	if overlays.get("ideal_path", false):
		var route := PackedVector2Array()
		for room_plan in graph.plan.ideal_route():
			route.append(graph.rooms[room_plan.key].seed * px)
		if route.size() > 1:
			draw_polyline(route, Color(1.0, 0.3, 0.75, 0.9), width * 2.0)
	if overlays.get("passages", false):
		for passage in graph.passages.values():
			var a := graph.rooms[passage.a].seed * px
			var b := graph.rooms[passage.b].seed * px
			draw_line(a, b, PASSAGE_COLORS[passage.kind], width * 1.5)
			draw_circle(Vector2(passage.spot) * px, maxf(width * 2.0, 2.0), PASSAGE_COLORS[passage.kind])
	if overlays.get("outlines", false):
		for room in graph.room_list:
			var polygon := _scaled(room.polygon, px)
			polygon.append(polygon[0])
			draw_polyline(polygon, Color(1, 1, 1, 0.55), width)
	if overlays.get("roles", false):
		for room in graph.room_list:
			draw_circle(room.seed * px, maxf(2.0, 2.5 / (camera.zoom.x if camera != null else 1.0)), ROLE_COLORS[room.role])
	if overlays.get("roles", false) or overlays.get("zones", false) or overlays.get("challenge", false):
		var zoom := camera.zoom.x if camera != null else 1.0
		var font_size := maxi(2, roundi(DebugState.UI_FONT_SIZE / zoom))
		for room in graph.room_list:
			var parts: Array[String] = []
			if overlays.get("zones", false):
				parts.append(String(room.plan.zone))
			if overlays.get("roles", false):
				parts.append("%s e%d" % [room.role_name(), int(room.get_meta("encounter_count", 0))])
			if overlays.get("challenge", false):
				parts.append("C%d" % room.plan.challenge)
			draw_string(DebugState.UI_FONT, room.seed * px + Vector2(3, -3) / zoom, " · ".join(parts),
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.85))


static func _scaled(points: PackedVector2Array, factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(point * factor)
	return out


static func _key_color(key: String, alpha: float) -> Color:
	return Color.from_hsv(float(posmod(hash(key), 360)) / 360.0, 0.55, 0.9, alpha)
