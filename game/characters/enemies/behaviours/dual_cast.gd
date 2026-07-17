extends FireWhenInRange
class_name DualCast

# FireWhenInRange with a second weapon woven into the same telegraph: when the secondary
# has come off cooldown the released shot is the secondary instead of the primary, so the
# rare payload (mandraker's fireball) replaces a regular shot rather than stacking on top.

@export var secondary_weapon_path: NodePath
@export var secondary_weapon_data: SpellResource

@onready var _secondary: CreatureSpellCaster = get_node(secondary_weapon_path)

func _ready() -> void:
	super()
	if secondary_weapon_data:
		_secondary.setup_for_creature(secondary_weapon_data)

func _fire(player: Node2D) -> void:
	if _secondary.can_cast:
		_secondary.try_cast(creature.global_position, player.global_position)
		return
	super(player)
