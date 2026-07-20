extends FireWhenInRange
class_name DualCast

# FireWhenInRange with a second spell woven into the same telegraph: when the secondary
# has come off cooldown the released shot is the secondary instead of the primary, so the
# rare payload (mandraker's fireball) replaces a regular shot rather than stacking on top.

@export var secondary_caster_path: NodePath
@export var secondary_spell: SpellResource

@onready var _secondary: SpellCaster = get_node(secondary_caster_path)

func _fire(player: Node2D) -> void:
	if _secondary.ready_for(secondary_spell):
		_secondary.cast(secondary_spell, (player.global_position - creature.global_position).normalized())
		return
	super(player)
