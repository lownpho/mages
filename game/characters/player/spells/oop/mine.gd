extends Node2D

## Mine effect (Oop, Ploop): dropped where it was cast, it arms on a delay and goes off when
## something it hunts touches it. Deliberately a dumb object — no AI, no health, no hurtbox —
## so it can't be shot, drawn away or disarmed.
##
## Detonating spawns the ordinary bullet-spell burst with the MINE as the caster, so the
## shots come out of the ground rather than out of the mage.

const BURST := preload("res://characters/player/spells/bullet_spell.tscn")

## A cast drops three, scattered around the caster like Whumf's clouds but on random
## bearings: no lane to read and step over, and no way to place one exactly, which is the
## trade for three of them. Each lands between these radii, and no two land closer than
## MIN_GAP_TILES, so the set covers ground instead of stacking into one fat mine.
const COUNT := 3
const NEAR_TILES := 1.0
const FAR_TILES := 2.0
const MIN_GAP_TILES := 1.6

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
var _caster: Node2D = null
var _extra_offsets: Array[Vector2] = []

@onready var _trigger: Area2D = $Trigger
@onready var _sprite: AnimatedSprite2D = $Sprite

## `offset` is where around the caster this one lands. The cast leaves it null — that mine
## scatters the whole set, keeps one spot and drops its siblings on the rest once it's in
## the tree, so the caster still only ever spawns one effect.
func setup(spell: SpellResource, caster: Node2D, offset: Variant = null) -> void:
	data = spell
	_caster = caster
	var ctx := CastContext.new(spell, caster)
	# A direction, never the cursor (see GlobalInput): it is the lane the payload fires
	# along, even though the mine no longer lands on it.
	_aim = ctx.aim
	if offset == null:
		_extra_offsets = _scatter()
		offset = _extra_offsets.pop_back()
	global_position = ctx.origin + offset
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
	for offset in _extra_offsets:
		var extra: Node2D = data.effect_scene.instantiate()
		extra.setup(data, _caster, offset)
		get_tree().root.add_child(extra)

## COUNT spots around the caster, in pixels, spread apart where the dice allow it.
# ponytail: rejection sampling on a fixed budget — the gap is a preference, not a promise.
# If three mines ever have to be guaranteed apart, place them on jittered thirds of a circle.
func _scatter() -> Array[Vector2]:
	var spots: Array[Vector2] = []
	for i in COUNT:
		var spot := _random_spot()
		for attempt in 20:
			var clear := true
			for other in spots:
				clear = clear and spot.distance_to(other) >= MIN_GAP_TILES * GameConstants.PX_PER_TILE
			if clear:
				break
			spot = _random_spot()
		spots.append(spot)
	return spots

func _random_spot() -> Vector2:
	var reach := randf_range(NEAR_TILES, FAR_TILES) * GameConstants.PX_PER_TILE
	return Vector2(reach, 0).rotated(randf() * TAU)

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
