extends Node2D

## ChargeDash: drives the caster in the aim direction at high speed for a short
## duration (via the generic Player.start_dash hook), firing a bullet out each
## side at 90° every fire_interval. Movement is a player capability; the volleys
## are plain BaseBullets on the caster's bullet layer, so it's faction-agnostic.

const _BulletScene = preload("res://items/bullets/base_bullet.tscn")

var data: ChargeDashResource
var _caster: Node2D
var skill: int = 0
var caster_speed: int = 0
var _layer: int = 0
var _dir: Vector2 = Vector2.RIGHT
var _elapsed: float = 0.0
var _fire_accum: float = 0.0

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	_caster = caster
	skill = caster.skill
	var spd = caster.get("speed")
	caster_speed = spd if spd != null else 0
	_dir = caster.get_aim_direction()
	if _dir == Vector2.ZERO:
		_dir = Vector2.RIGHT

func _ready() -> void:
	var layer_override = _caster.get("bullet_collision_layer")
	_layer = layer_override if layer_override != null else GameConstants.LAYER_PLAYER_BULLETS
	if _caster.has_method("start_dash"):
		_caster.start_dash(_dir, data.dash_speed, data.duration)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_caster) or data.bullet == null:
		queue_free()
		return
	_elapsed += delta
	_fire_accum += delta
	if _fire_accum >= data.fire_interval:
		_fire_accum = 0.0
		_fire_sides()
	if _elapsed >= data.duration:
		queue_free()

func _fire_sides() -> void:
	for side in [_dir.rotated(PI / 2), _dir.rotated(-PI / 2)]:
		var bullet = _BulletScene.instantiate()
		bullet.data = data.bullet
		bullet.collision_layer = _layer
		bullet.base_direction = side
		bullet.skill = skill
		bullet.speed = caster_speed
		bullet.global_position = _caster.global_position
		get_tree().root.add_child.call_deferred(bullet)
