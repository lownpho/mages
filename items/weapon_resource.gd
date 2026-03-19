extends ItemResource
class_name WeaponResource

@export_group("Weapon")
@export var fire_pattern: FirePattern
@export var bullet_scene: PackedScene
@export var fire_cooldown: float = 0.5
@export var mana_cost: int = 1

func get_item_type() -> GlobalInventory.ItemType:
	return GlobalInventory.ItemType.WEAPON
