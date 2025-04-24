extends Area2D

@export var type: GlobalDefs.ItemType
@export var item: PackedScene

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	GlobalEvent.item_picked_up.emit(name, type, item)
	queue_free()
