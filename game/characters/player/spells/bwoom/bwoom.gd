extends CharacterBody2D

## Bwoom channel effect: a ball charges in front of the caster, growing one sprite frame per
## tick while the button is held, then flies off along the caster's aim when the channel ends
## — SpellCaster calls channel_released() on button release or at the cast_time cap. The hit
## is the spell's ScalingProfile once per tick held, so a full charge is worth max_ticks
## taps and the release is a real decision.
##
## It sits on the caster's bullet layer but stays OUT of the "bullets" group, so hurtboxes
## take damage from it without despawning it — that's the piercing line the design asks for.
## Only walls stop it; it dies on a wall, off-screen, at range, or on a fallback lifetime.
##
## Faction-agnostic like every other effect: aim, layer and stats come from CastContext, so
## an owl charging a shot at the player runs this exact file.

const LIFETIME = 3.0
## Hold distance from the caster along the aim while charging.
const HOLD_OFFSET_TILES = 1.5
## Collision radius per charge stage, matching the art frames' opaque extents.
const STAGE_RADII_PX = [2.0, 3.0, 4.0, 6.0, 8.0]

var data: BwoomResource
var ctx: CastContext

var _caster: Node2D
var _elapsed := 0.0
var _launched := false
var _damage := 0
var _travelled := 0.0

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	ctx = CastContext.new(spell, caster)
	_caster = caster
	global_position = _hold_position()

func _ready() -> void:
	collision_layer = ctx.bullet_layer
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
		return
	_travelled += velocity.length() * delta
	if _travelled >= data.range_tiles * GameConstants.PX_PER_TILE:
		queue_free()

func channel_released() -> void:
	if _launched:
		return
	_launched = true
	var ticks := _ticks()
	_damage = ticks * (ctx.damage.compute(ctx.skill, ctx.speed, ctx.defence) if ctx.damage else 0)
	velocity = _aim() * data.speed_tiles * GameConstants.PX_PER_TILE
	var shape := CircleShape2D.new()
	shape.radius = STAGE_RADII_PX[mini(ticks, STAGE_RADII_PX.size()) - 1]
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

# Live, not the aim sampled at setup: the ball tracks where the caster is pointing for the
# whole channel, so a held charge can be walked onto a target.
func _aim() -> Vector2:
	if not is_instance_valid(_caster):
		return ctx.aim
	var aim: Vector2 = _caster.get_aim_direction()
	return aim if aim != Vector2.ZERO else ctx.aim

func _hold_position() -> Vector2:
	return _caster.global_position + _aim() * HOLD_OFFSET_TILES * GameConstants.PX_PER_TILE
