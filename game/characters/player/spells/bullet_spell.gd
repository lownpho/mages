extends Node2D

## Generic bullet-spell effect: every shot_interval it fires the spell's
## FirePattern from the caster's position along the caster's current aim
## direction, until max_shots are spent (1 = a single projectile) — then it
## emits finished (SpellCaster starts the cooldown there) and frees itself.
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
# Accumulated rotation_per_shot, and (for aim_independent) the burst's random bearing.
var _drift: float = 0.0
var _base_angle: float = 0.0

func setup(spell: SpellResource, p_caster: Node2D) -> void:
	data = spell
	caster = p_caster
	ctx = CastContext.new(spell, p_caster)

func _ready() -> void:
	_shots_left = data.max_shots
	_cadence = data.shot_interval  # banked, so shot 1 fires as soon as the gate opens
	_base_angle = randf() * TAU
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
	# Re-sample aim per shot: the burst tracks the caster as it turns — unless the spell
	# is aim_independent, where it paints from its own fixed bearing instead.
	var direction: Vector2 = Vector2.RIGHT.rotated(_base_angle) if data.aim_independent \
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
		var position: Vector2 = caster.global_position \
			+ dirs[i] * (randf() * data.fire_pattern.spawn_offset) + lateral
		ctx.spawn_bullet(data.bullet, dirs[i], position, target)

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
