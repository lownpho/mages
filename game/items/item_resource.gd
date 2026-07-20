extends Resource
class_name ItemResource

@export var icon: Texture2D
@export_group("Stat Modifiers")
@export var skill_modifier: int = 0
@export var speed_modifier: int = 0
@export var max_health_modifier: int = 0
@export var defence_modifier: int = 0

func get_item_type() -> GlobalInventory.ItemType:
	return GlobalInventory.ItemType.OTHER

# Equip modifiers — flat stat changes applied while the item is equipped, as
# [icon_key, value] rows (the view maps keys to icons), always signed so a gain
# reads "+N". This is the only tooltip content the UI shows (see ui_slot.gd).
func get_modifiers() -> Array:
	var rows := []
	if skill_modifier != 0: rows.append(["skill", "%+d" % skill_modifier])
	if speed_modifier != 0: rows.append(["speed", "%+d" % speed_modifier])
	if max_health_modifier != 0: rows.append(["health", "%+d" % max_health_modifier])
	if defence_modifier != 0: rows.append(["defence", "%+d" % defence_modifier])
	return rows
