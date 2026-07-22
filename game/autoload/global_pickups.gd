extends Node

## Autoloaded. Turns player-discarded items (item_dropped) and creature loot (loot_dropped)
## into collectable pickups in the running scene. Lives globally so every gameplay scene
## gets drops with no per-scene wiring — a scene that wants its pickups under a tidy,
## z-sorted container just puts that node in the "pickups" group; otherwise they go to the
## scene root.

const _PICKUP_SCENE: PackedScene = preload("res://items/pickup_item.tscn")

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
	pickup.global_position = at
	# Loot often drops from a death handled inside a bullet's collision callback, i.e.
	# while the physics server is flushing queries — bringing the pickup's Area2D online
	# then is illegal, so defer the add until the flush completes.
	container.add_child.call_deferred(pickup)

# Random nudge within a tile so simultaneous drops don't stack on the same pixel.
func _scatter() -> Vector2:
	return Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * GameConstants.PX_PER_TILE
