extends ItemResource
class_name WeaponResource

enum FirePattern { SINGLE, RING }

@export_group("Weapon")
@export var fire_pattern: FirePattern = FirePattern.SINGLE
@export var bullet_scene: PackedScene
@export var fire_cooldown: float = 0.5
@export var mana_cost: int = 1
@export var num_bullets: int = 1 ## Only used for RING

func get_item_type() -> GlobalInventory.ItemType:
	return GlobalInventory.ItemType.WEAPON
