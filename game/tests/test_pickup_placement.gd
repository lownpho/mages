extends Node2D
## Headless drop-placement test: a drop aimed inside terrain lands on open floor instead, a
## drop aimed at open floor stays roughly where it was aimed, and a walled-in drop still
## appears. Run:
##   godot --headless --path game res://tests/test_pickup_placement.tscn

## Half-width of the test walls, in pixels. Wider than the widest nudge ring, so a drop at
## the centre can only escape sideways — and, once boxed in, not at all.
const WALL := 64.0

var _fails: Array[String] = []


func _ready() -> void:
	var item := ItemResource.new()

	# A tree line: solid from y = 0 down, open above it.
	_wall(Rect2(-WALL, 0.0, WALL * 2.0, WALL))
	var inside := await _drop(item, Vector2(0.0, 8.0))
	if inside == null:
		_fails.append("a drop into terrain spawned nothing")
	elif inside.global_position.y >= 0.0:
		_fails.append("a drop into terrain stayed in it, at %s" % inside.global_position)

	# Open floor: only the random scatter moves it, never a nudge.
	var aimed := Vector2(0.0, -32.0)
	var open := await _drop(item, aimed)
	if open == null:
		_fails.append("a drop onto open floor spawned nothing")
	elif open.global_position.distance_to(aimed) > GameConstants.PX_PER_TILE * 1.5:
		_fails.append("a drop onto open floor moved to %s, want near %s" % [open.global_position, aimed])

	# Boxed in: nothing within reach is open, so the drop keeps what it was aimed at rather
	# than vanishing.
	_wall(Rect2(-WALL, -WALL * 2.0, WALL * 2.0, WALL * 2.0))
	if await _drop(item, aimed) == null:
		_fails.append("a walled-in drop spawned nothing")

	if _fails.is_empty():
		print("ALL PASS")
	else:
		for f in _fails:
			print("  - ", f)
		print("FAILED: %d" % _fails.size())
	get_tree().quit()


## A static body on the terrain layer covering `rect`.
func _wall(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var box := RectangleShape2D.new()
	box.size = rect.size
	var shape := CollisionShape2D.new()
	shape.shape = box
	shape.position = rect.get_center()
	body.add_child(shape)
	add_child(body)


## Emits a drop and returns the pickup it spawned, once the deferred placement has run.
func _drop(item: ItemResource, at: Vector2) -> Node2D:
	var before := _pickups().size()
	GlobalEvent.loot_dropped.emit(item, at)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var after := _pickups()
	return after[-1] if after.size() > before else null


func _pickups() -> Array[Node]:
	var out: Array[Node] = []
	for child in get_children():
		if child is Area2D:
			out.append(child)
	return out
