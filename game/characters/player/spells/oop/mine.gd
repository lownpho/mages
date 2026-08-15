extends Node2D

## Mine effect (Oop, Ploop): dropped where it was cast, it arms on a delay and goes off when
## something it hunts touches it. Deliberately a dumb object — no AI, no health, no hurtbox —
## so it can't be shot, drawn away or disarmed.
##
## Detonating spawns the ordinary bullet-spell burst with the MINE as the caster, so the
## shots come out of the ground rather than out of the mage.

const BURST := preload("res://characters/player/spells/bullet_spell.tscn")

## How far ahead of the caster the mine lands. One tile: far enough to place it *in front of*
## what's coming rather than under your own feet, close enough that you never have to lead it.
const DROP_TILES := 1.0

var data: MineResource

# The caster contract the detonation's own CastContext samples back off us, mirrored from
# whoever dropped the mine so the payload scales and picks its faction exactly as if they
# had cast it where it sits.
var skill: int = 0
var speed: int = 0
var defence: int = 0
var bullet_collision_layer: int = GameConstants.LAYER_PLAYER_BULLETS
var target_groups: Array = ["enemies"]

var _aim: Vector2 = Vector2.RIGHT

@onready var _trigger: Area2D = $Trigger
@onready var _sprite: AnimatedSprite2D = $Sprite

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	var ctx := CastContext.new(spell, caster)
	# A direction, never the cursor (see GlobalInput), so a stick places it exactly like a
	# mouse does — one tile along whichever way you're pointing.
	_aim = ctx.aim
	global_position = ctx.origin + _aim * DROP_TILES * GameConstants.PX_PER_TILE
	skill = ctx.skill
	speed = ctx.speed
	defence = ctx.defence
	bullet_collision_layer = ctx.bullet_layer
	target_groups = ctx.target_groups

## The burst reads this like it reads any caster's — the lane the mine was dropped facing,
## which is what a directional pattern (a cone, a flank) would fire along.
func get_aim_direction() -> Vector2:
	return _aim

func _ready() -> void:
	set_physics_process(false)
	# No cast behind it: something put the scene in the tree without setup() — a stale
	# reference to it as a summon's minion is how that happens. There is nothing to arm,
	# and a live mine with no payload would sit there forever.
	if data == null:
		queue_free()
		return
	_sprite.sprite_frames = data.frames
	_sprite.play("idle")
	get_tree().create_timer(data.arm_time).timeout.connect(_arm)
	get_tree().create_timer(data.lifetime).timeout.connect(queue_free)

func _arm() -> void:
	set_physics_process(true)

# Polled rather than driven by body_entered: something already standing on the mine when it
# arms never "enters" it, and that case — dropping one under the enemy on your heels — is
# exactly the one a trap must not miss.
func _physics_process(_delta: float) -> void:
	for body in _trigger.get_overlapping_bodies():
		for group in target_groups:
			if body.is_in_group(group):
				_detonate()
				return

func _detonate() -> void:
	set_physics_process(false)
	_sprite.play("fuse")
	var burst: Node2D = BURST.instantiate()
	burst.setup(data, self)
	get_tree().root.add_child(burst)
	# The burst samples the mine every shot, so the mine outlives it by exactly one burst.
	burst.finished.connect(queue_free)
