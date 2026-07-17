extends Node2D

## Generic weapon-spell burst effect: every shot_interval it fires the spell's
## FirePattern from the caster's position along the caster's current aim
## direction, until max_shots are spent or burst_window elapses after the first
## shot — then it emits finished (SpellCaster starts the cooldown there) and
## frees itself.
##
## Exclusive spells cancel it: a newer weapon burst (Player.register_burst) or
## a starting cast/channel (Player.cancel_bursts) calls interrupt(), which ends
## the burst onto its full cooldown. Instant spells leave it firing.
## Faction-agnostic: aim, bullet layer, and homing target groups all come from
## the caster (player defaults when it lacks the creature exports).

signal finished

const _BulletScene = preload("res://items/bullets/base_bullet.tscn")

var data: WeaponSpellResource
var caster: Node2D
var skill: int = 0

var _shots_left: int = 0
var _cadence: float = 0.0
var _window_left: float = -1.0  # starts counting down at the first shot
var _finished: bool = false

func setup(spell: SpellResource, p_caster: Node2D) -> void:
	data = spell
	caster = p_caster
	skill = caster.skill

func _ready() -> void:
	_shots_left = data.max_shots
	_cadence = data.shot_interval  # banked, so shot 1 fires as soon as the gate opens
	if caster.has_method("register_burst"):
		caster.register_burst(self)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(caster):
		_finish()
		return
	if _window_left >= 0.0:
		_window_left -= delta
		if _window_left <= 0.0:
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
	_shots_left -= 1
	if _shots_left <= 0:
		_finish()

func _fire() -> void:
	if _window_left < 0.0:
		_window_left = data.burst_window
	var direction: Vector2 = caster.get_aim_direction()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var layer_override = caster.get("bullet_collision_layer")
	var layer: int = layer_override if layer_override != null else GameConstants.LAYER_PLAYER_BULLETS
	var target: Node2D = null
	if data.bullet.homing:
		target = _find_target(direction)
	var dirs := data.fire_pattern.get_directions(direction)
	var offsets := data.fire_pattern.get_offsets(direction)
	for i in dirs.size():
		var lateral: Vector2 = offsets[i] if i < offsets.size() else Vector2.ZERO
		var bullet = _BulletScene.instantiate()
		bullet.data = data.bullet
		bullet.collision_layer = layer
		bullet.position = caster.global_position \
			+ dirs[i] * (randf() * data.fire_pattern.spawn_offset) + lateral
		bullet.base_direction = dirs[i]
		bullet.skill = skill
		var spd = caster.get("speed")
		bullet.speed = spd if spd != null else 0
		bullet.pierce = caster.get("bullets_pierce") == true
		bullet.target = target
		get_tree().root.add_child(bullet)

# Homing lock along the aim direction (never the cursor position): the nearest
# hostile inside the bullet's assist cone, out to its range.
func _find_target(direction: Vector2) -> Node2D:
	var groups = caster.get("target_groups")
	if groups == null:
		groups = ["enemies"]
	var range_px: float = data.bullet.range_tiles * GameConstants.PX_PER_TILE
	var from := caster.global_position
	var best: Node2D = null
	for group in groups:
		var hit := AimAssist.nearest_in_cone(get_tree(), group, from, direction,
			range_px, data.bullet.homing_cone_deg)
		if hit and (best == null
				or from.distance_squared_to(hit.global_position)
					< from.distance_squared_to(best.global_position)):
			best = hit
	return best

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
