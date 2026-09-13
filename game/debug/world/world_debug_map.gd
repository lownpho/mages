class_name WorldDebugMap
extends Control
## Complete graph map: independent of tiles, streaming and fog. Wheel zooms around the cursor,
## middle/right drag pans, hover reports the Room, and left click teleports to clear floor there.

signal teleport_requested(tile: Vector2i)

var graph: WorldGraph
## Hovering a Room builds its encounters on demand to report their count.
var encounters: WorldEncounters
var overlays: Dictionary = {}
var entered_rooms: Dictionary[String, bool] = {}
var zoom := 0.22
var pan := Vector2.ZERO
var hovered: GeneratedRoom
var _dragging := false
var _last_mouse := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	gui_input.connect(_on_gui_input)
	mouse_exited.connect(func() -> void:
		hovered = null
		tooltip_text = ""
		queue_redraw())


func set_data(world_graph: WorldGraph, enabled: Dictionary, reset_view := false) -> void:
	graph = world_graph
	overlays = enabled
	if reset_view and graph != null:
		fit_world()
	queue_redraw()


func set_entered_rooms(entered: Dictionary[String, bool]) -> void:
	entered_rooms = entered
	queue_redraw()


func fit_world() -> void:
	if graph == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var world_size := Vector2(graph.plan.size * WorldPlan.CELL)
	zoom = minf(size.x / maxf(world_size.x, 1.0), size.y / maxf(world_size.y, 1.0)) * 0.92
	pan = world_size * 0.5
	queue_redraw()


func tile_at(local: Vector2) -> Vector2:
	return (local - size * 0.5) / zoom + pan


func screen_at(tile: Vector2) -> Vector2:
	return (tile - pan) * zoom + size * 0.5


func _on_gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _dragging:
			pan -= motion.relative / zoom
		else:
			_update_hover(motion.position)
		_last_mouse = motion.position
		queue_redraw()
		accept_event()
		return
	var button := event as InputEventMouseButton
	if button == null:
		return
	if button.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
		_dragging = button.pressed
		_last_mouse = button.position
		accept_event()
	elif button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var before := tile_at(button.position)
		zoom = clampf(zoom * (1.25 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 0.015, 3.0)
		pan += before - tile_at(button.position)
		queue_redraw()
		accept_event()
	elif button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		teleport_requested.emit(Vector2i(tile_at(button.position).round()))
		accept_event()


func _update_hover(local: Vector2) -> void:
	if graph == null:
		return
	hovered = null
	var point := tile_at(local)
	for room in graph.room_list:
		if Geometry2D.is_point_in_polygon(point, room.polygon):
			hovered = room
			break
	if hovered == null:
		tooltip_text = ""
	else:
		tooltip_text = "%s\n%s / %s\n%s · Challenge %d · encounters %d" % [hovered.key(),
			hovered.plan.biome, hovered.plan.zone, hovered.role_name(), hovered.plan.challenge,
			encounters.encounter_count(hovered) if encounters != null else 0]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.04, 0.055))
	if graph == null:
		return
	for room in graph.room_list:
		var points := _points(room.polygon)
		var presentation := graph.plan.content.biomes[room.plan.biome].presentation
		var fill := presentation.map_floor_color if presentation != null else Color(0.25, 0.3, 0.35)
		if overlays.get("zones", false):
			fill = WorldDebugOverlay._key_color("%s/%s" % [room.plan.biome, room.plan.zone], 0.75)
		if overlays.get("challenge", false):
			var high := maxi(1, graph.plan.content.biomes[room.plan.biome].exit_challenge)
			fill = Color.from_hsv(0.33 - 0.33 * room.plan.challenge / high, 0.8, 0.85, 0.75)
		if overlays.get("discovery", false):
			fill = fill.lightened(0.25) if entered_rooms.has(room.key()) else fill.darkened(0.55)
		draw_colored_polygon(points, fill)
		if overlays.get("outlines", true):
			points.append(points[0])
			draw_polyline(points, Color(0.75, 0.8, 0.88, 0.65), 1.0)
	if overlays.get("macro_grid", false):
		for coord in graph.plan.cells:
			var rect := Rect2(screen_at(Vector2(coord * WorldPlan.CELL)), Vector2.ONE * WorldPlan.CELL * zoom)
			draw_rect(rect, Color(0.45, 0.75, 1.0, 0.6), false, 1.0)
		var folded := PackedVector2Array()
		for coord in graph.plan.path:
			folded.append(screen_at(Vector2(coord * WorldPlan.CELL) + Vector2.ONE * WorldPlan.CELL * 0.5))
		if folded.size() > 1:
			draw_polyline(folded, Color(0.45, 0.75, 1.0, 0.9), 2.0)
	if overlays.get("ideal_path", false):
		var route := PackedVector2Array()
		for room_plan in graph.plan.ideal_route():
			route.append(screen_at(graph.rooms[room_plan.key].seed))
		if route.size() > 1:
			draw_polyline(route, Color(1.0, 0.3, 0.75), 2.0)
	if overlays.get("passages", false):
		for passage in graph.passages.values():
			draw_line(screen_at(graph.rooms[passage.a].seed), screen_at(graph.rooms[passage.b].seed),
					WorldDebugOverlay.PASSAGE_COLORS[passage.kind], 1.5)
	if overlays.get("roles", false):
		for room in graph.room_list:
			draw_circle(screen_at(room.seed), 2.0, WorldDebugOverlay.ROLE_COLORS[room.role])
	if hovered != null:
		var outline := _points(hovered.polygon)
		outline.append(outline[0])
		draw_polyline(outline, Color.WHITE, 2.0)


func _points(polygon: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in polygon:
		out.append(screen_at(point))
	return out
