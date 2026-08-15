extends Node2D
class_name BulletSpell

## Generic bullet-spell effect: every shot_interval it fires the spell's
## FirePattern from the caster's position along the caster's current aim
## direction, until max_shots are spent (1 = a single projectile) — then it
## emits finished (SpellCaster starts the cooldown there) and frees itself.
##
## Three aim modes, all data: it tracks the caster shot to shot (default), commits to the
## lane it started with (lock_aim), or paints from its own random bearing (aim_independent).
##
## Exclusive spells cancel it: a newer burst (Player.register_burst) or a
## starting cast/channel (Player.cancel_bursts) calls interrupt(), which ends
## the burst onto its full cooldown. Instant spells leave it firing.
## Faction-agnostic through CastContext (aim, bullet layer, stats, homing).

signal finished

var data: BulletSpellResource
var caster: Node2D
var ctx: CastContext

var _shots_left: int = 0
var _cadence: float = 0.0
var _finished: bool = false
# Accumulated rotation_per_shot, and the bearing every shot fires along while _locked.
var _drift: float = 0.0
var _base_angle: float = 0.0
var _locked: bool = false

func setup(spell: SpellResource, p_caster: Node2D) -> void:
	data = spell
	caster = p_caster
	ctx = CastContext.new(spell, p_caster)

func _ready() -> void:
	_shots_left = data.max_shots
	_cadence = data.shot_interval  # banked, so shot 1 fires as soon as the gate opens
	# The lane is decided here, once, for both committed modes — and _ready is the moment the
	# burst begins, so a spell with a wind-up locks onto where the target was when the
	# telegraph ended rather than where they were when it started.
	_locked = data.aim_independent or data.lock_aim
	if data.aim_independent:
		_base_angle = randf() * TAU
	elif data.lock_aim:
		var aim: Vector2 = caster.get_aim_direction()
		_base_angle = aim.angle() if aim != Vector2.ZERO else 0.0
	if caster.has_method("register_burst"):
		caster.register_burst(self)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(caster):
		_finish()
		return
	# Cadence accrues while suspended (capped at one shot) so resuming fires
	# immediately instead of waiting out a fresh interval.
	_cadence = minf(_cadence + delta, data.shot_interval)
	if _cadence < data.shot_interval:
		return
	if caster.has_method("can_burst_fire") and not caster.can_burst_fire(self):
		return
	_fire()
	_cadence = 0.0
	_drift += data.rotation_per_shot
	_shots_left -= 1
	if _shots_left <= 0:
		_finish()

func _fire() -> void:
	# Re-sample aim per shot so the burst tracks the caster as it turns — unless the lane was
	# committed at the start (lock_aim, aim_independent), in which case every shot reuses it.
	var direction: Vector2 = Vector2.RIGHT.rotated(_base_angle) if _locked \
		else caster.get_aim_direction()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	direction = direction.rotated(deg_to_rad(_drift))
	var target: Node2D = null
	var homing := data.bullet.homing()
	if homing:
		target = ctx.find_target(direction,
			data.bullet.range_tiles * GameConstants.PX_PER_TILE, homing.cone_deg)
	var dirs := data.fire_pattern.get_directions(direction)
	var offsets := data.fire_pattern.get_offsets(direction)
	for i in dirs.size():
		var lateral: Vector2 = offsets[i] if i < offsets.size() else Vector2.ZERO
		var spawn_pos: Vector2 = caster.global_position \
			+ dirs[i] * (randf() * data.fire_pattern.spawn_offset) + lateral
		ctx.spawn_bullet(data.bullet, dirs[i], spawn_pos, target)

## Cancel the burst: it stops firing and goes on cooldown, exactly as if it
## had run out — finished fires as usual.
func interrupt() -> void:
	_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	set_physics_process(false)
	if is_instance_valid(caster) and caster.has_method("unregister_burst"):
		caster.unregister_burst(self)
	finished.emit()
	queue_free()
