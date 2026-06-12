extends Resource
class_name LootDrop

## One entry in an enemy's drop list: the item and its independent drop chance.
@export var item: ItemResource
@export_range(0.0, 1.0) var chance: float = 1.0

func roll() -> bool:
	return item != null and randf() < chance
