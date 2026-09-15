class_name PowerCells
extends RefCounted
## Small analytic power diagrams avoid rasterizing the World during startup. Interiors query the
## same partition at tile time. Each shared border is found once by clipping the bisector against
## all other seeds and the macro cell; no triangulation or approximate adjacency is required.


## Each Room's power cell within the macro cell's convex outline.
static func polygons(rooms: Array[GeneratedRoom], outline: PackedVector2Array) -> void:
	for room in rooms:
		var poly := outline
		var reach := _reach(poly, room.seed)
		for other in rooms:
			if other == room:
				continue
			var normal := other.seed - room.seed
			var distance := normal.length()
			# A bisector beyond every vertex can't cut the polygon.
			if distance > 0.0 and (distance * distance + room.radius * room.radius - other.radius * other.radius) / (2.0 * distance) >= reach:
				continue
			var limit := (other.seed.length_squared() - room.seed.length_squared()
					+ room.radius * room.radius - other.radius * other.radius) * 0.5
			poly = clip(poly, normal, limit)
			if poly.is_empty():
				break
			reach = _reach(poly, room.seed)
		room.polygon = poly


## The farthest vertex's distance from a point.
static func _reach(poly: PackedVector2Array, point: Vector2) -> float:
	var farthest := 0.0
	for vertex in poly:
		farthest = maxf(farthest, vertex.distance_squared_to(point))
	return sqrt(farthest)


static func clip(poly: PackedVector2Array, normal: Vector2, limit: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if poly.is_empty():
		return out
	var before := poly[-1]
	var before_d := before.dot(normal) - limit
	for point in poly:
		var d := point.dot(normal) - limit
		if (d <= 0.0) != (before_d <= 0.0):
			out.append(before.lerp(point, before_d / (before_d - d)))
		if d <= 0.0:
			out.append(point)
		before = point
		before_d = d
	return out


static func border(a: GeneratedRoom, b: GeneratedRoom) -> PackedVector2Array:
	var normal := b.seed - a.seed
	var limit := (b.seed.length_squared() - a.seed.length_squared() + a.radius * a.radius - b.radius * b.radius) * 0.5
	var points := PackedVector2Array()
	for p in a.polygon:
		if absf(p.dot(normal) - limit) < 0.02:
			points.append(p)
	if points.size() < 2 or points[0].distance_to(points[-1]) < 1.0:
		return PackedVector2Array()
	return PackedVector2Array([points[0], points[-1]])
