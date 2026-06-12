extends CharacterBody2D

## Bwoom channel effect: a ball charges in front of the caster, growing one
## sprite frame per tick while the button is held — the caster keeps moving
## (channel_while_moving) and the ball follows, tracking the cursor.
## channel_released() — called by SpellCaster on button release, mana-out, or
## the channel cap — fires it toward the cursor. It sits on the player-bullets
## layer but stays out of the "bullets" group, so hurtboxes damage it without
## despawning it — that's the piercing. Only walls stop it; dies on walls,
## off-screen, or after a fallback lifetime.

const LIFETIME = 3.0
## Hold distance from the caster toward the cursor while charging.
const HOLD_OFFSET_TILES = 1.5
## Collision radius per charge stage, matching the art frames' opaque extents.
const STAGE_RADII_PX = [2.0, 3.0, 4.0, 6.0, 8.0]

var data: BwoomResource
var skill: int = 0

var _caster: Node2D
var _elapsed := 0.0
var _launched := false
var _damage := 0

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	skill = caster.skill
	_caster = caster
	global_position = _hold_position()

func _ready() -> void:
	$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)

func _process(delta: float) -> void:
	if _launched:
		return
	_elapsed += delta
	$Sprite2D.frame = _ticks() - 1
	if is_instance_valid(_caster):
		global_position = _hold_position()
	# Safety net: if the caster died mid-channel, launch at the cap ourselves.
	if _elapsed > data.cast_time + 0.1:
		channel_released()

func _physics_process(delta: float) -> void:
	if not _launched:
		return
	if move_and_collide(velocity * delta):
		queue_free()

func channel_released() -> void:
	if _launched:
		return
	_launched = true
	var ticks := _ticks()
	_damage = ticks * roundi(data.base_damage + skill * data.skill_scaling)
	var direction := (get_global_mouse_position() - global_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	velocity = direction * data.speed_tiles * GameConstants.PX_PER_TILE
	var shape := CircleShape2D.new()
	shape.radius = STAGE_RADII_PX[ticks - 1]
	$CollisionShape2D.shape = shape
	$CollisionShape2D.set_deferred("disabled", false)
	var lifetime_timer := Timer.new()
	lifetime_timer.one_shot = true
	lifetime_timer.autostart = true
	lifetime_timer.wait_time = LIFETIME
	lifetime_timer.timeout.connect(queue_free)
	add_child(lifetime_timer)

func get_damage() -> int:
	return _damage

func _ticks() -> int:
	# 50 ms grace so a release on the same frame as a tick still counts it;
	# a bare tap still fires the smallest, one-tick ball.
	var tick_interval := data.cast_time / data.max_ticks
	return clampi(int((_elapsed + 0.05) / tick_interval), 1, data.max_ticks)

func _hold_position() -> Vector2:
	var aim := (_caster.get_global_mouse_position() - _caster.global_position).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	return _caster.global_position + aim * HOLD_OFFSET_TILES * GameConstants.PX_PER_TILE
