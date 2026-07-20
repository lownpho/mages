extends Behaviour
class_name Volley

# Plants its feet, casts `spell` once, and holds the state open until that burst finishes
# — then → done_state. The burst's whole shape is the spell's own data (max_shots,
# shot_interval, rotation_per_shot, aim_independent), so the behaviour keeps no count and
# no cadence of its own: one beat is one cast. The spell's `cooldown` is what it says on
# the tin — the recovery before the dispatcher may roll this beat again.
#
# A parting reaction with no range gate: an aimed burst gives up when its target vanishes,
# but an aim_independent spray keeps painting the arena.

@export var caster_path: NodePath
@export var spell: SpellResource
@export var attack_anim: String = "attack"
@export var done_state: String = "Idle"

@onready var _caster: SpellCaster = get_node(caster_path)

# Don't let a dispatcher roll this beat while the spell is still cooling — it would
# stand there doing nothing until the cooldown lapsed.
func can_run() -> bool:
	return _caster.ready_for(spell)

func enter() -> void:
	creature.velocity = Vector2.ZERO
	creature.play(attack_anim)
	var player := creature.get_target()
	_caster.cast(spell, aim_at(player) if player else Vector2.ZERO)

func exit() -> void:
	# Leaving mid-burst takes the remaining shots with us, onto the full cooldown.
	_caster.interrupt(spell)

func physics_update(_delta: float) -> void:
	var player := creature.get_target()
	if player:
		creature.face(player.global_position.x - creature.global_position.x)
	elif _requires_target():
		go_to(done_state)
		return
	if not _caster.is_casting(spell):
		go_to(done_state)

# An absolute-aim spray doesn't care whether the player is still there.
func _requires_target() -> bool:
	return not (spell is BulletSpellResource and spell.aim_independent)
