@tool
extends Area2D

@export var item: ItemResource: # Runs on assignment so the editor icon stays in sync.
	set(value):
		item = value
		_update_sprite()

## When set, the carried item is rolled from this table at pickup time and `item` is
## ignored. The contents are unknown until grabbed, so author a mystery icon on the
## Sprite2D in the scene rather than letting `item` drive it.
@export var table: LootTable

func _ready() -> void:
	_update_sprite()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)

func _update_sprite() -> void:
	if not is_node_ready():
		return
	if table: # mystery pickup keeps its authored icon
		return
	$Sprite2D.texture = item.icon if item and item.icon else null

func _on_body_entered(_body: Node2D) -> void:
	var resolved: ItemResource = table.pick() if table else item
	if resolved == null:
		return
	var slot = GlobalInventory.bag_slots.add_at_first_empty(resolved)
	if slot:
		GlobalEvent.item_picked_up.emit(slot)
		queue_free()
