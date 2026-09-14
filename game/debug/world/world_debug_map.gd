class_name WorldDebugMap
extends Control
## Complete graph map: independent of tiles, streaming and fog. Wheel zooms around the cursor,
## middle/right drag pans, hover reports the Room, and left click teleports to clear floor there.

signal teleport_requested(tile: Vector2i)

## A role dot's radius in tiles, kept between these many map pixels.
const ROLE_DOT_TILES := 2.5
const ROLE_DOT_MIN := 1.25
const ROLE_DOT_MAX := 4.0
## Minimap marker colours, by MapState marker kind, with pins last.
const MARKER_NAMES: Array[StringName] = [&"boss", &"fountain", &"door", &"sign", &"npc", &"pin"]
const MARKER_COLORS: Array[Color] = [Palette.YELLOW, Palette.PINK, Palette.BLUE, Palette.GREEN,
		Palette.PURPLE, Palette.ORANGE]
## A marker's side and an enemy dot's radius in tiles, kept between these many map pixels.
const MARKER_TILES := 3.0
const MARKER_MIN := 2.0
const MARKER_MAX := 5.0
const ENEMY_TILES := 1.5
const ENEMY_MIN := 1.0
const ENEMY_MAX := 3.0
## Layers that change while the Map is open, so it redraws every frame they are on.
const LIVE_LAYERS := ["player", "enemies", "chunks", "follow"]

var graph: WorldGraph
## Hovering a Room builds its encounters on demand to report their count.
var encounters: WorldEncounters
var overlays: Dictionary = {}
var entered_rooms: Dictionary[String, bool] = {}
var zoom := 0.22
var pan := Vector2.ZERO
var hovered: GeneratedRoom
## What the minimap layers follow: the player and its camera, and the chunks streamed around it.
var player: Node2D
var streamer: ChunkStreamer
var _dragging := false
var _last_mouse := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	gui_input.connect(_on_gui_input)
	# The panel resizes the Map a layout pass after opening its tab; frame the World in its real size.
	resized.connect(fit_world)
	mouse_exited.connect(func() -> void:
		hovered = null
		tooltip_text = ""
		queue_redraw())


func _process(_delta: float) -> void:
	if graph == null or not is_visible_in_tree():
		return
	if overlays.get("follow", false) and is_instance_valid(player):
		pan = player.global_position / GameConstants.PX_PER_TILE
	if LIVE_LAYERS.any(func(key: String) -> bool: return overlays.get(key, false)):
		queue_redraw()


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
		tooltip_text = "%s\n%s / %s\n%s, Challenge %d, encounters %d" % [hovered.key(),
			hovered.plan.biome, hovered.plan.zone, hovered.role_name(), hovered.plan.challenge,
			encounters.encounter_count(hovered) if encounters != null else 0]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.04, 0.055))
	if graph == null:
		return
	var biome_fills := WorldDebugOverlay.biome_colors(graph.plan.content, 0.75)
	for room in graph.room_list:
		var points := _points(room.polygon)
		var presentation := graph.plan.content.biomes[room.plan.biome].presentation
		var fill := presentation.map_floor_color if presentation != null else Color(0.25, 0.3, 0.35)
		if overlays.get("biomes", false):
			fill = biome_fills[room.plan.biome]
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
		# Dots grow with zoom, so a fitted World of hundreds of Rooms isn't buried under them.
		var radius := clampf(zoom * ROLE_DOT_TILES, ROLE_DOT_MIN, ROLE_DOT_MAX)
		for room in graph.room_list:
			draw_circle(screen_at(room.seed), radius, WorldDebugOverlay.ROLE_COLORS[room.role])
	if overlays.get("chunks", false) and streamer != null:
		var chunk := Vector2.ONE * streamer.chunk_tiles
		for coord in streamer.loaded_chunk_coords():
			draw_rect(Rect2(screen_at(Vector2(coord) * chunk), chunk * zoom), Color(1, 1, 1, 0.14))
	if overlays.get("markers", false) and GlobalMap.active != null:
		# Every Room's markers, where the minimap shows only discovered ones.
		var side := clampf(zoom * MARKER_TILES, MARKER_MIN, MARKER_MAX)
		for room in graph.room_list:
			if room.role == GeneratedRoom.Role.BOSS:
				_draw_marker(graph.tile_of(room.seed), MapState.MARKER_BOSS, side * 1.5)
			for site in room.sites:
				var kind: int = GlobalMap.active._marker_kind(site)
				if kind >= 0:
					_draw_marker(site.spot, kind, side)
		for pin: Vector2i in GlobalMap.active.pins:
			_draw_marker(pin, MARKER_COLORS.size() - 1, side)
	if overlays.get("enemies", false):
		var radius := clampf(zoom * ENEMY_TILES, ENEMY_MIN, ENEMY_MAX)
		for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
			draw_circle(screen_at(enemy.global_position / GameConstants.PX_PER_TILE), radius, Palette.RED)
	if overlays.get("player", false) and is_instance_valid(player):
		# The player and the box its camera sees.
		var camera := player.get_viewport().get_camera_2d()
		if camera != null:
			var view := player.get_viewport().get_visible_rect().size / camera.zoom / GameConstants.PX_PER_TILE
			var centre := camera.get_screen_center_position() / GameConstants.PX_PER_TILE
			draw_rect(Rect2(screen_at(centre - view * 0.5), view * zoom), Color(1, 1, 1, 0.8), false, 1.0)
		var at := screen_at(player.global_position / GameConstants.PX_PER_TILE)
		draw_circle(at, 3.0, Color.BLACK)
		draw_circle(at, 2.0, Palette.WHITE)
	if hovered != null:
		var outline := _points(hovered.polygon)
		outline.append(outline[0])
		draw_polyline(outline, Color.WHITE, 2.0)


func _draw_marker(tile: Vector2i, kind: int, side: float) -> void:
	var centre := screen_at(Vector2(tile) + Vector2(0.5, 0.5))
	draw_rect(Rect2(centre - Vector2.ONE * side * 0.5, Vector2.ONE * side), MARKER_COLORS[kind])


func _points(polygon: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in polygon:
		out.append(screen_at(point))
	return out
