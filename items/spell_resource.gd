extends ItemResource
class_name SpellResource

@export_group("Spell")
@export var effect_scene: PackedScene
@export var cooldown: float = 1.0
@export var mana_cost: int = 5
@export var base_damage: int = 0

func get_item_type() -> GlobalInventory.ItemType:
	return GlobalInventory.ItemType.SPELL
