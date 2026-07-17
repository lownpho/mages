extends Node2D

## Shing: arms a one-shot echo on the caster's SpellCaster so the NEXT spell
## casts twice. All the logic lives in SpellCaster.arm_echo() (deferred, so Shing
## never echoes itself); this effect just calls it and frees. Self-cast.

func setup(_spell: SpellResource, caster: Node2D) -> void:
	global_position = caster.global_position
	var sc = caster.get_node_or_null("SpellCaster")
	if sc and sc.has_method("arm_echo"):
		sc.arm_echo()

func _ready() -> void:
	queue_free()
