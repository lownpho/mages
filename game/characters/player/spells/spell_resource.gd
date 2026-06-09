extends ItemResource
class_name SpellResource

@export_group("Spell")
## Scene spawned when the cast resolves. Its root must implement
## setup(spell: SpellResource, caster: Node2D) and position itself from the caster.
@export var effect_scene: PackedScene
@export var cooldown: float = 1.0
@export var mana_cost: int = 5
## Seconds the player is rooted in the Cast state before the effect spawns. 0 = instant.
@export var cast_time: float = 0.0
@export var base_damage: float = 0.0
@export var skill_scaling: float = 0.0

func get_item_type() -> GlobalInventory.ItemType:
	return GlobalInventory.ItemType.SPELL
