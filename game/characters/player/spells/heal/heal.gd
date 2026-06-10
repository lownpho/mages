extends Node2D

## Heal effect: instantly restores health to the caster, capped at max. The
## spell icon drifts up over the caster as feedback, then the node frees.
## Uses the base SpellResource — healing is base_damage + skill × scaling.

var data: SpellResource
var caster: CharacterBody2D

func setup(spell: SpellResource, p_caster: Node2D) -> void:
	data = spell
	caster = p_caster
	global_position = p_caster.global_position

func _ready() -> void:
	var amount := roundi(data.base_damage + caster.skill * data.skill_scaling)
	caster.health = mini(caster.health + amount, caster.max_health)
	GlobalEvent.player_health_changed.emit(caster.health)

	$Sprite2D.texture = data.icon
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y - 12.0, 0.6)
	tween.tween_callback(queue_free)
