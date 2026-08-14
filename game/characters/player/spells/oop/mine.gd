extends Node2D

## Mine effect (Oop, Ploop): dropped where it was cast, it arms on a delay and goes off when
## something it hunts touches it. It is deliberately a dumb object — no AI, no targeting, no
## health, no hurtbox — so it can't be shot, drawn away or disarmed. A mine is a hazard you
## walk around.
##
## It carries no firing code either: detonating spawns the ordinary bullet-spell burst with
## the mine's own resource, and with the MINE as the caster so the shots come out of the
## ground rather than out of the mage. That makes Oop's blast and Ploop's dart ring pure
## data, and the mine faction-agnostic — it hunts whatever the caster hunts.

const BURST := preload("res://characters/player/spells/bullet_spell.tscn")

## How far ahead of the caster the mine lands. One tile: far enough to place it *in front of*
## what's coming rather than under your own feet, close enough that you never have to lead it.
const DROP_TILES := 1.0

var data: MineResource

# The caster contract CastContext samples, mirrored off whoever dropped the mine so the
# payload scales and picks its faction exactly as if they had cast it where it sits.
var skill: int = 0
var speed: int = 0
var defence: int = 0
var bullet_collision_layer: int = GameConstants.LAYER_PLAYER_BULLETS
var target_groups: Array = ["enemies"]

var _aim: Vector2 = Vector2.RIGHT
var _armed: bool = false

@onready var _trigger: Area2D = $Trigger
@onready var _sprite: AnimatedSprite2D = $Sprite

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	_aim = caster.get_aim_direction()
	# A direction, never the cursor (see GlobalInput), so a stick places it exactly like a
	# mouse does — one tile along whichever way you're pointing.
	global_position = caster.global_position + _aim * DROP_TILES * GameConstants.PX_PER_TILE
	skill = _stat(caster, "skill")
	# Bonus speed only — base_speed is the walk floor, not a power stat (see CastContext).
	speed = _stat(caster, "speed") - _stat(caster, "base_speed")
	defence = _stat(caster, "defence")
	var layer = caster.get("bullet_collision_layer")
	if layer != null:
		bullet_collision_layer = layer
	var groups = caster.get("target_groups")
	if groups != null:
		target_groups = groups

func _stat(caster: Node2D, key: String) -> int:
	var value = caster.get(key)
	return int(value) if value != null else 0

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
	get_tree().create_timer(data.arm_time).timeout.connect(_arm)
	if data.lifetime > 0.0:
		get_tree().create_timer(data.lifetime).timeout.connect(queue_free)

func _arm() -> void:
	_armed = true
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
	_armed = false
	set_physics_process(false)
	_trigger.monitoring = false
	_sprite.play("fuse")
	var burst: Node2D = BURST.instantiate()
	burst.setup(data, self)
	get_tree().root.add_child(burst)
	# The burst samples the mine every shot, so the mine outlives it by exactly one burst.
	burst.finished.connect(queue_free)
