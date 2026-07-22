@tool
extends Area2D

@export var item: ItemResource: # Runs on assignment so the editor icon stays in sync.
	set(value):
		item = value
		_resolve()

## When set, the carried item is rolled once from this table when the pickup enters the
## world and `item` is ignored.
@export var table: LootTable

## Seconds before the pickup arms. Connecting body_entered only after the delay means a
## pickup that spawns on top of the player (e.g. an item discarded toward screen centre)
## isn't collected on the same frame — it waits for the player to leave and re-enter.
@export var pickup_delay := 0.4

# The concrete item this pickup carries. Resolved once (rolling `table` at most once) so the
# icon on the ground can never disagree with what lands in the bag.
var _carried: ItemResource


func _ready() -> void:
	_resolve()
	if Engine.is_editor_hint():
		return
	if pickup_delay > 0.0:
		await get_tree().create_timer(pickup_delay).timeout
	body_entered.connect(_on_body_entered)

# Settle on the carried item and show its icon. Re-runs in the editor on edits for a live
# preview; at runtime the single _ready() call is what freezes a table roll.
func _resolve() -> void:
	if not is_node_ready():
		return
	_carried = item if item else table.pick() if table else null
	$Sprite2D.texture = _carried.icon if _carried else null

func _on_body_entered(_body: Node2D) -> void:
	if GlobalInventory.has_item(_carried):
		return
	var slot = GlobalInventory.bag_slots.add_at_first_empty(_carried)
	if slot:
		GlobalEvent.item_picked_up.emit(slot)
		queue_free()
