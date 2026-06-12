extends Node2D

## One Kaboom meteor: marks its impact point on the ground while the delay
## runs, then streaks down onto it and explodes. All damage comes from the
## explosion's DamageZone — the falling meteor itself carries none.

var damage: int = 0
var impact_delay: float = 1.5
var mark_texture: Texture2D
var explosion_frames: SpriteFrames
var aoe_tiles: float = 3.0

@export var fall_time: float = 0.25
@export var fall_height_tiles: float = 10.0

var _falling := false
var _fall_speed: float = 0.0

@onready var meteor: AnimatedSprite2D = $Meteor
@onready var explosion: DamageZone = $Explosion
@onready var explosion_sprite: AnimatedSprite2D = $Explosion/AnimatedSprite2D

func _ready() -> void:
	$Mark.texture = mark_texture
	explosion.damage = damage
	explosion_sprite.sprite_frames = explosion_frames
	var shape := CircleShape2D.new()
	shape.radius = aoe_tiles * GameConstants.PX_PER_TILE / 2.0
	$Explosion/CollisionShape2D.shape = shape

	var fall_px := fall_height_tiles * GameConstants.PX_PER_TILE
	_fall_speed = fall_px / fall_time
	meteor.position = Vector2(0, -fall_px)

	var fall_timer := Timer.new()
	fall_timer.one_shot = true
	fall_timer.autostart = true
	fall_timer.wait_time = maxf(impact_delay - fall_time, 0.05)
	fall_timer.timeout.connect(_start_fall)
	add_child(fall_timer)

func _start_fall() -> void:
	_falling = true
	meteor.show()
	meteor.play("burn")

func _process(delta: float) -> void:
	if not _falling:
		return
	meteor.position.y = minf(meteor.position.y + _fall_speed * delta, 0.0)
	if meteor.position.y >= 0.0:
		_impact()

func _impact() -> void:
	_falling = false
	$Mark.hide()
	meteor.hide()
	$Explosion/CollisionShape2D.set_deferred("disabled", false)
	explosion_sprite.show()
	explosion_sprite.play("explode")
	explosion_sprite.animation_finished.connect(queue_free)
