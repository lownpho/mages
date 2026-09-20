extends Node

## Autoloaded. Turns player-discarded items (item_dropped) and creature loot (loot_dropped)
## into collectable pickups in the running scene. Lives globally so every gameplay scene
## gets drops with no per-scene wiring — a scene that wants its pickups under a tidy,
## z-sorted container just puts that node in the "pickups" group; otherwise they go to the
## scene root.

const _PICKUP_SCENE: PackedScene = preload("res://items/pickup_item.tscn")

## Physics layer 1, the walls and rocks the player can't walk through.
const _TERRAIN_MASK := 1
## How far out a drop aimed into terrain may be nudged to find floor, in pixels.
const _NUDGE_RINGS: Array[float] = [6.0, 12.0, 18.0, 24.0]
const _NUDGE_STEPS := 8

func _ready() -> void:
	GlobalEvent.item_dropped.connect(_on_item_dropped)
	GlobalEvent.loot_dropped.connect(_on_loot_dropped)

# Player discard: drop at the cursor — except on gamepad, where there is no
# cursor, so the item lands at the mage's feet instead.
func _on_item_dropped(item: ItemResource) -> void:
	var scene := get_tree().current_scene
	if scene is Node2D:
		var player := get_tree().get_first_node_in_group("player")
		var at: Vector2 = player.global_position if GlobalInput.using_gamepad and player \
				else scene.get_global_mouse_position()
		_spawn(item, at + _scatter())

func _on_loot_dropped(item: ItemResource, pos: Vector2) -> void:
	_spawn(item, pos + _scatter())

func _spawn(item: ItemResource, at: Vector2) -> void:
	var container := get_tree().get_first_node_in_group("pickups")
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return
	var pickup := _PICKUP_SCENE.instantiate()
	pickup.item = item
	# Loot often drops from a death handled inside a bullet's collision callback, i.e.
	# while the physics server is flushing queries — bringing the pickup's Area2D online
	# then is illegal, and so is asking the space state where the walls are, so both the
	# add and the search for open ground wait for the flush to complete.
	_place.call_deferred(container, pickup, at)

# Puts the pickup down where the player can actually reach it. A drop aimed into terrain (a
# creature dying against a tree line, a gift handed out beside one) walks outward in rings
# until it finds open floor; a spot fully walled in keeps what it was aimed at.
func _place(container: Node, pickup: Node2D, at: Vector2) -> void:
	if not is_instance_valid(container):
		pickup.free()
		return
	container.add_child(pickup)
	pickup.global_position = _open_spot(pickup.get_world_2d().direct_space_state, at)

func _open_spot(space: PhysicsDirectSpaceState2D, at: Vector2) -> Vector2:
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = _TERRAIN_MASK
	query.position = at
	if space.intersect_point(query, 1).is_empty():
		return at
	for radius in _NUDGE_RINGS:
		for step in _NUDGE_STEPS:
			query.position = at + Vector2.RIGHT.rotated(TAU * step / _NUDGE_STEPS) * radius
			if space.intersect_point(query, 1).is_empty():
				return query.position
	return at

# Random nudge within a tile so simultaneous drops don't stack on the same pixel.
func _scatter() -> Vector2:
	return Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * GameConstants.PX_PER_TILE
