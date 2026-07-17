extends ItemResource
class_name SpellResource

@export_group("Spell")
## Scene spawned when the cast resolves. Its root must implement
## setup(spell: SpellResource, caster: Node2D) and position itself from the caster.
@export var effect_scene: PackedScene
@export var cooldown: float = 1.0
## Seconds the player is rooted in the Cast state before the effect spawns. 0 = instant.
@export var cast_time: float = 0.0
## Spawn the effect when the cast begins instead of when it resolves — aim is
## sampled at button press and the effect runs during the wind-up (e.g. Kaboom
## marking its impact points while the player is still casting).
@export var effect_at_cast_start: bool = false
## Hold-to-channel: the effect spawns at press (aim locks there) and cast_time
## caps the channel (0 = uncapped). When the button is released or the cap
## hits, the caster calls channel_released() on the effect — channeled
## effects must implement it.
@export var channeled: bool = false
## Channeled only: don't root the caster while channeling — the player keeps
## moving while the button is held (e.g. Bwoom charging on the move).
@export var channel_while_moving: bool = false
@export var base_damage: float = 0.0
@export var skill_scaling: float = 0.0
## Extra damage per point of caster speed, mirroring skill_scaling. Lets a spell
## scale with the speed stat instead of skill. 0 = no speed scaling.
@export var speed_scaling: float = 0.0
## Extra damage per point of caster defence (Halo, Bwoom, …). 0 = none.
@export var defence_scaling: float = 0.0

func get_item_type() -> GlobalInventory.ItemType:
	return GlobalInventory.ItemType.SPELL

# Standard spell-damage formula: base plus per-stat scaling. Effects that deal
# damage should call this so speed_scaling is honoured uniformly. speed defaults
# to 0 so skill-only callers (and enemy casts) are unaffected.
func damage_for(p_skill: int, p_speed: int = 0, p_defence: int = 0) -> int:
	return roundi(base_damage + p_skill * skill_scaling + p_speed * speed_scaling \
		+ p_defence * defence_scaling)

func get_stats() -> Array:
	var rows := []
	if base_damage > 0.0: rows.append(["damage", "%d" % int(base_damage)])
	rows.append(["cooldown", "%.1f" % cooldown])
	if cast_time > 0.0: rows.append(["cast", "%.1f" % cast_time])
	return rows
