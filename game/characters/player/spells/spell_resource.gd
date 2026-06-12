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
## Spawn the effect when the cast begins instead of when it resolves — aim is
## sampled at button press and the effect runs during the wind-up (e.g. Kaboom
## marking its impact points while the player is still casting).
@export var effect_at_cast_start: bool = false
@export var base_damage: float = 0.0
@export var skill_scaling: float = 0.0

func get_item_type() -> GlobalInventory.ItemType:
	return GlobalInventory.ItemType.SPELL
