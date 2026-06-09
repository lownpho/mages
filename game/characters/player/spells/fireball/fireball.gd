extends CharacterBody2D

## Fireball spell projectile: flies toward the cursor captured when the cast
## resolves and explodes on the first hit (terrain or enemy) or at max range.
## All damage is dealt by the explosion's DamageZone — the projectile carries none,
## so a direct hit and a splash hit are worth the same.

var data: FireballResource
var skill: int = 0

var _direction: Vector2 = Vector2.RIGHT
var _exploded: bool = false

@onready var explosion: DamageZone = $Explosion
@onready var explosion_sprite: AnimatedSprite2D = $Explosion/AnimatedSprite2D

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	skill = caster.skill
	global_position = caster.global_position
	_direction = (caster.get_global_mouse_position() - caster.global_position).normalized()

func _ready() -> void:
	$Sprite2D.texture = data.icon
	velocity = _direction * data.speed_tiles * GameConstants.PX_PER_TILE

	explosion.damage = roundi(data.base_damage + skill * data.skill_scaling)
	explosion_sprite.sprite_frames = data.explosion_frames
	var shape := CircleShape2D.new()
	shape.radius = data.aoe_tiles * GameConstants.PX_PER_TILE / 2.0
	$Explosion/CollisionShape2D.shape = shape

	# Explode at max range if nothing was hit on the way.
	var range_timer := Timer.new()
	range_timer.one_shot = true
	range_timer.autostart = true
	range_timer.wait_time = data.range_tiles / data.speed_tiles
	range_timer.timeout.connect(_explode)
	add_child(range_timer)

func _physics_process(delta: float) -> void:
	if _exploded:
		return
	if move_and_collide(velocity * delta):
		_explode()

func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	$Sprite2D.hide()
	$CollisionShape2D.set_deferred("disabled", true)
	$Explosion/CollisionShape2D.set_deferred("disabled", false)
	explosion_sprite.show()
	explosion_sprite.play("explode")
	explosion_sprite.animation_finished.connect(queue_free)
