extends ItemResource
class_name SpellResource

@export_group("Spell")
## Scene spawned when the cast resolves. Its root must implement
## setup(spell: SpellResource, caster: Node2D) and position itself from the caster.
@export var effect_scene: PackedScene
@export var cooldown: float = 1.0
## Seconds the player is rooted in the Cast state before the effect spawns. 0 = instant.
@export var cast_time: float = 0.0
## Hold-to-channel: the effect spawns at press (aim locks there) and cast_time
## caps the channel (0 = uncapped). When the button is released or the cap
## hits, the caster calls channel_released() on the effect — channeled
## effects must implement it. The caster is rooted for the channel.
@export var channeled: bool = false

func get_item_type() -> GlobalInventory.ItemType:
	return GlobalInventory.ItemType.SPELL
