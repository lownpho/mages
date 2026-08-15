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
## Exempt from SpellCaster.repeat_penalty — for a spell there is no point rotating
## away from (a heal, a summon), which would otherwise be taxed for being cast the
## only way it can be. Exempt casts also leave another spell's repeat chain intact.
@export var repeat_exempt: bool = false
## Line shown above the stat grid in the slot tooltip. Never seen on an enemy's
## bespoke casts, which are never held in a slot.
@export_multiline var blurb: String = "I didn't take notes on this"

func get_item_type() -> GlobalInventory.ItemType:
	return GlobalInventory.ItemType.SPELL

func get_modifiers() -> Array:
	if cooldown <= 0.0:
		return super()
	return super() + [["cooldown", String.num(cooldown)]]
