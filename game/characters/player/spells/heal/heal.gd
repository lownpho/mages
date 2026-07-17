extends Node2D

## Heal effect: restores health to the caster, capped at max. A red plus-sign
## aura rises over the caster (mirroring the focus aura) as feedback, then the
## node frees.
## Uses the base SpellResource — healing is damage_for(), defence-scaled per the
## design (the survivability stat feeds the survivability button).

var data: SpellResource
var caster: CharacterBody2D

func setup(spell: SpellResource, p_caster: Node2D) -> void:
	data = spell
	caster = p_caster
	global_position = p_caster.global_position

func _ready() -> void:
	var amount := data.damage_for(caster.skill, 0, caster.defence)
	caster.health = mini(caster.health + amount, caster.max_health)
	GlobalEvent.player_health_changed.emit(caster.health)

	var tween := create_tween()
	tween.tween_property($Aura, "modulate:a", 0.0, 0.45).set_delay(0.15)
	tween.tween_callback(queue_free)
