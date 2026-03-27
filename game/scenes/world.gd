extends Node2D

const PickupScene = preload("res://items/pickup_item.tscn")

func _ready() -> void:
	GlobalEvent.item_dropped.connect(_on_item_dropped)

func _on_item_dropped(item: ItemResource) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	var pickup = PickupScene.instantiate()
	pickup.item = item
	# This leads to possible items getting stuck in walls.
	# ddsIt's fun so I'm leaving it in
	pickup.global_position = player.global_position + Vector2(0, 32)
	add_child(pickup)
