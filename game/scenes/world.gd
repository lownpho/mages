extends Node2D

const PickupScene = preload("res://items/pickup_item.tscn")

func _ready() -> void:
	GlobalEvent.item_dropped.connect(_on_item_dropped)
	GlobalEvent.loot_dropped.connect(_on_loot_dropped)

func _on_item_dropped(item: ItemResource) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	# This leads to possible items getting stuck in walls.
	# It's fun so I'm leaving it in
	_spawn_pickup(item, get_global_mouse_position())

func _on_loot_dropped(item: ItemResource, pos: Vector2) -> void:
	# Scatter within a tile so simultaneous drops don't stack on the same pixel.
	var offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * GameConstants.PX_PER_TILE
	_spawn_pickup(item, pos + offset)

func _spawn_pickup(item: ItemResource, at: Vector2) -> void:
	var pickup = PickupScene.instantiate()
	pickup.item = item
	pickup.global_position = at
	add_child(pickup)
