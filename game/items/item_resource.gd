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

# Tooltip rows as [icon_key, value] pairs; the view maps keys to icons and shows
# active stats and modifiers in two separate groups.

# Active stats — the item's own functional values (damage, cost, cooldown…),
# shown plain. Base items have none; subclasses fill this in.
func get_stats() -> Array:
	return []

# Equip modifiers — flat stat changes applied while the item is equipped, always
# signed so a gain reads "+N". Shares icons with active stats; the group
# separation disambiguates them.
func get_modifiers() -> Array:
	var rows := []
	if skill_modifier != 0: rows.append(["skill", "%+d" % skill_modifier])
	if speed_modifier != 0: rows.append(["speed", "%+d" % speed_modifier])
	if max_health_modifier != 0: rows.append(["health", "%+d" % max_health_modifier])
	if defence_modifier != 0: rows.append(["defence", "%+d" % defence_modifier])
	return rows
