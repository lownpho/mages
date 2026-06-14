extends Resource
class_name ItemResource

@export var icon: Texture2D
@export_group("Stat Modifiers")
@export var skill_modifier: int = 0
@export var speed_modifier: int = 0
@export var max_health_modifier: int = 0
@export var max_mana_modifier: int = 0
@export var defence_modifier: int = 0

func get_item_type() -> GlobalInventory.ItemType:
	return GlobalInventory.ItemType.OTHER
