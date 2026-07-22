extends Behaviour
class_name Cast

# One beat = one cast(). The spell owns the whole burst — length, cadence, aim drift — so
# this keeps no shot counter and no cadence of its own; it owns only WHEN the burst starts,
# what the sprite does while it runs, and when to give up on it.
#
# The wind-up is the spell's `cast_time`, the same number the player's cast engine already
# honours, and the sprite is driven FROM it (see Creature.play_fitted) rather than the shot
# being triggered by a sprite frame — so an enemy's tell lives in its spell data and can't
# drift from its art. Recovery is not this state's business either: the beat hands off to
# `done_state` the moment the burst ends, and a Hold pointed back here parks the creature
# until `cooldown` lapses.

@export var caster_path: NodePath
@export var spell: SpellResource
@export var done_state: String = "Idle"

@export_group("Range")
## Optional: while set, the beat bails the moment the target clears this probe instead of
## lobbing the rest of its shots into the void. Empty = fire regardless of where they went.
@export var attack_probe_path: NodePath
## Where clearing the probe bails to — required whenever attack_probe_path is set, unused
## (and left empty) otherwise.
@export var out_of_range_state: String = ""
## Hysteresis (px) the exit check reaches past the attack probe, so a target loitering on
## the boundary can't strobe the creature between closing and firing. Usually unnecessary
## now that recovery is its own state — the creature holds position while it cools.
@export var exit_margin: float = 0.0

@export_group("Animation")
## Pose held during `cast_time`. Empty reuses attack_anim. A non-looping tag has its strike
## frame fitted to the wind-up; a looping one (a held guard) simply runs.
@export var windup_anim: String = ""
@export var attack_anim: String = "attack"
## Incoming damage during the wind-up; <1 makes the telegraph a bad moment to trade.
@export var windup_damage_scale: float = 1.0

@onready var _caster: SpellCaster = get_node(caster_path)

var _probe: RayCast2D
var _exit_probe: RayCast2D
var _winding_up: bool = false

func _ready() -> void:
	super()
	_caster.cast_resolved.connect(_on_cast_resolved)
	if attack_probe_path == NodePath():
		return
	_probe = get_node(attack_probe_path)
	if exit_margin <= 0.0:
		return
	# Child of the attack probe so it inherits the per-frame look_at aim for free; only
	# its length differs.
	_exit_probe = RayCast2D.new()
	_exit_probe.collision_mask = _probe.collision_mask
	_exit_probe.target_position = Vector2(_probe.target_position.length() + exit_margin, 0)
	_exit_probe.hit_from_inside = true
	_exit_probe.enabled = false
	_probe.add_child(_exit_probe)

# Don't let a dispatcher roll this beat — or a Hold hand off to it — while the spell is
# still cooling; it would just stand there until the cooldown lapsed.
func _ready_to_run() -> bool:
	return _caster.ready_for(spell)

func enter() -> void:
	creature.velocity = Vector2.ZERO
	if _probe:
		_probe.enabled = true
	if _exit_probe:
		_exit_probe.enabled = true
	# Cast first, then dress the beat to match. A wind-up only exists if the cast actually
	# started — a rejected cast (spell still cooling, host busy) must NOT leave us in a
	# telegraph that never resolves, or the beat's wind-up early-out freezes the creature.
	var player := creature.get_target()
	var started := _caster.cast(spell, aim_at(player) if player else Vector2.ZERO)
	_winding_up = started and spell.cast_time > 0.0 and not spell.channeled
	if _winding_up:
		creature.incoming_damage_scale = windup_damage_scale
		creature.play_fitted(windup_anim if windup_anim != "" else attack_anim, spell.cast_time)
	else:
		creature.play(attack_anim)

func exit() -> void:
	# Leaving mid-beat takes the rest of it with us, onto the full cooldown — whether
	# that's a spent telegraph or the shots still owed.
	_end_windup()
	_caster.cancel(spell)
	_caster.interrupt(spell)
	if _probe:
		_probe.enabled = false
	if _exit_probe:
		_exit_probe.enabled = false

func physics_update(_delta: float) -> void:
	var player := creature.get_target()

	# A wind-up is a committed telegraph: once it starts the shot goes off, wherever the
	# target went. Guard against a stale flag (the caster already resolved or never started)
	# so we can never sit here frozen.
	if _winding_up:
		if _caster.is_casting(spell):
			_track_aim(player)
			return
		_end_windup()

	# While the cast is live — wind-up done, shots still in flight — the shots are already
	# committed. Track a strafing target for shots 2..n, but never bail: cutting the burst
	# here just eats an attack the creature already paid its telegraph for (a single-shot
	# spell fires a frame after resolve, so an eager bail cancels it outright). Re-chasing is
	# the recovery state's job, once the burst is actually spent.
	if _caster.is_casting(spell):
		_track_aim(player)
		return

	# Cast spent. If the target has cleared the attack probe, re-close now; otherwise let the
	# strike/recovery animation land its final frame before handing off, so the pose doesn't
	# snap mid-swing into the next state's idle.
	if player and _probe:
		_probe.look_at(player.global_position)
		if not creature.probe_sees(_exit_probe if _exit_probe else _probe):
			go_to(out_of_range_state)
			return
	_track_aim(player)
	if _anim_settled():
		go_to(done_state)

# cast() stamps aim once, at the first shot. bullet_spell re-samples the caster every shot so
# a burst can track a strafing target — but only the beat knows where the target went, so it
# keeps the aim honest for shots 2..n (and for the pending wind-up shot).
func _track_aim(player: Node2D) -> void:
	if not player:
		return
	creature.face(player.global_position.x - creature.global_position.x)
	if _is_aimed():
		creature.aim_direction = aim_at(player)

# True once the current (non-looping) animation has run out its final frame, so the beat can
# hand off without clipping the strike pose. A looping or missing anim has no final frame to
# wait on, so it settles immediately.
func _anim_settled() -> bool:
	var frames := creature.sprite.sprite_frames
	var cur: StringName = creature.sprite.animation
	if frames == null or not frames.has_animation(cur) or frames.get_animation_loop(cur):
		return true
	return not creature.sprite.is_playing()

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
	creature.sprite.speed_scale = 1.0

# Whether this beat is pointed at someone: an absolute-aim spray fires from its own
# bearing, so it neither tracks the target nor cares that they left.
func _is_aimed() -> bool:
	return not (spell is BulletSpellResource and spell.aim_independent)
