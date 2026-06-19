@tool
extends Area2D

@export var item: ItemResource: # Runs on assignment so the editor icon stays in sync.
	set(value):
		item = value
		_update_sprite()

## When set, the carried item is rolled from this table at pickup time and `item` is ignored.
@export var table: LootTable


func _ready() -> void:
	_update_sprite()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)

func _update_sprite() -> void:
	if not is_node_ready():
		return

	var shown := item if item else table.pick() if table else null
	$Sprite2D.texture = shown.icon if shown else null

func _on_body_entered(_body: Node2D) -> void:
	var picked := item if item else table.pick() if table else null
	var slot = GlobalInventory.bag_slots.add_at_first_empty(picked)
	if slot:
		GlobalEvent.item_picked_up.emit(slot)
		queue_free()
