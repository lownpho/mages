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
## The telegraph, for a spell with a cast_time: the wind-up is the spell's own number, so
## the beat only supplies its look — a pose and, under 1.0, armour that makes the tell a
## bad time to trade. Both lapse the moment the spell resolves into its burst.
@export var windup_anim: String = ""
@export var windup_damage_scale: float = 1.0

@onready var _caster: SpellCaster = get_node(caster_path)

var _winding_up: bool = false

func _ready() -> void:
	super()
	_caster.cast_resolved.connect(_on_cast_resolved)

# Don't let a dispatcher roll this beat while the spell is still cooling — it would
# stand there doing nothing until the cooldown lapsed.
func can_run() -> bool:
	return _caster.ready_for(spell)

func enter() -> void:
	creature.velocity = Vector2.ZERO
	_winding_up = spell.cast_time > 0.0 and not spell.channeled
	creature.play(windup_anim if _winding_up and windup_anim != "" else attack_anim)
	if _winding_up:
		creature.incoming_damage_scale = windup_damage_scale
	var player := creature.get_target()
	_caster.cast(spell, aim_at(player) if player else Vector2.ZERO)

func exit() -> void:
	# Leaving mid-beat takes the rest of it with us, onto the full cooldown — whether
	# that's a spent telegraph or the shots still owed.
	_end_windup()
	_caster.cancel(spell)
	_caster.interrupt(spell)

func physics_update(_delta: float) -> void:
	var player := creature.get_target()
	if player:
		creature.face(player.global_position.x - creature.global_position.x)
		# cast() stamps aim once, at the first shot. bullet_spell re-samples the caster
		# every shot so a burst can track a strafing target — but only the beat knows
		# where the target went, so it has to keep the aim honest for shots 2..n.
		if _is_aimed():
			creature.aim_direction = aim_at(player)
	elif _is_aimed():
		go_to(done_state)
		return
	if not _caster.is_casting(spell):
		go_to(done_state)

# The caster is shared across every beat, so only our own spell landing counts.
func _on_cast_resolved(resolved: SpellResource) -> void:
	if resolved != spell or not _winding_up:
		return
	_end_windup()
	creature.play(attack_anim)

func _end_windup() -> void:
	if not _winding_up:
		return
	_winding_up = false
	creature.incoming_damage_scale = 1.0

# Whether this beat is pointed at someone: an absolute-aim spray fires from its own
# bearing, so it neither tracks the target nor cares that they left.
func _is_aimed() -> bool:
	return not (spell is BulletSpellResource and spell.aim_independent)
