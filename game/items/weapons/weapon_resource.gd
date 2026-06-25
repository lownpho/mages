extends ItemResource
class_name WeaponResource

@export_group("Weapon")
@export var fire_pattern: FirePattern
@export var bullet_data: BulletResource
@export var fire_cooldown: float = 0.5
@export var mana_cost: int = 1

func get_item_type() -> GlobalInventory.ItemType:
	return GlobalInventory.ItemType.WEAPON

func get_stats() -> Array:
	return [["damage", "%d" % int(bullet_data.base_damage)],
		["cooldown", "%.1f" % fire_cooldown],
		["mana", "%d" % mana_cost]]
