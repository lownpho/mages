extends Node
class_name PickupSpawner

## Turns item/loot drops into collectable pickups in the world. Listens on the global
## event bus for player-discarded items (item_dropped) and creature loot (loot_dropped)
## and instances a pickup into `container` for each. Any gameplay scene that wants drops
## to become pickups adds one of these; callers can also place a pickup directly via
## spawn(). Faction-agnostic and scene-agnostic — it knows nothing about who dropped what.

## Scene instanced per pickup. Must expose a settable `item` property (see pickup_item.tscn).
@export var pickup_scene: PackedScene = preload("res://items/pickup_item.tscn")

## Node the pickups are parented under (and whose canvas the cursor drop is read from).
## Falls back to the parent when left unset, so dropping this under a Node2D just works.
@export var container: Node2D

func _ready() -> void:
	if container == null and get_parent() is Node2D:
		container = get_parent()
	assert(container != null, "PickupSpawner needs a Node2D container")
	GlobalEvent.item_dropped.connect(_on_item_dropped)
	GlobalEvent.loot_dropped.connect(_on_loot_dropped)

## Place one pickup carrying `item` at world position `at`.
func spawn(item: ItemResource, at: Vector2) -> void:
	var pickup := pickup_scene.instantiate()
	pickup.item = item
	pickup.global_position = at
	# Loot often drops from a death handled inside a bullet's collision callback, i.e.
	# while the physics server is flushing queries — bringing the pickup's Area2D online
	# then is illegal, so defer the add until the flush completes.
	container.add_child.call_deferred(pickup)

# Player-discarded item: drop it at the cursor, but only while a player exists to discard it.
func _on_item_dropped(item: ItemResource) -> void:
	if get_tree().get_first_node_in_group("player"):
		spawn(item, container.get_global_mouse_position())

func _on_loot_dropped(item: ItemResource, pos: Vector2) -> void:
	# Scatter within a tile so simultaneous drops don't stack on the same pixel.
	var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * GameConstants.PX_PER_TILE
	spawn(item, pos + offset)
