extends RefCounted
class_name CastContext

## The cast environment a spell effect needs, sampled once from the caster at
## setup() so every effect reads it the same way instead of re-deriving it.
##
## Faction-agnostic by construction: `skill`, `target_groups`,
## `bullet_collision_layer` and `get_aim_direction()` are on the caster contract
## (player and Creature both), while stats a creature may lack (speed, defence,
## bullets_pierce) come through get() with safe defaults. Aim is always a
## direction — never a cursor position — so a controller stick can drive it.

var spell: SpellResource
var caster: Node2D
var origin: Vector2
var aim: Vector2      ## Unit aim direction (never Vector2.ZERO).
var skill: int
var speed: int
var defence: int
var bullet_layer: int
var target_groups: Array
var pierce: bool
## This cast's damage, read off the spell (bullets carry none — see BulletResource).
## null for spells that resolve their own number, like heal.
var damage: ScalingProfile

const _BulletScene = preload("res://items/bullets/base_bullet.tscn")

func _init(p_spell: SpellResource, p_caster: Node2D) -> void:
	spell = p_spell
	caster = p_caster
	origin = caster.global_position
	aim = caster.get_aim_direction()
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	skill = caster.skill
	speed = _stat("speed")
	defence = _stat("defence")
	# The faction fields live on Creature; the player lacks them, so default to
	# the player side (player-bullet layer, hostile = "enemies").
	var layer = caster.get("bullet_collision_layer")
	bullet_layer = layer if layer != null else GameConstants.LAYER_PLAYER_BULLETS
	var groups = caster.get("target_groups")
	target_groups = groups if groups != null else ["enemies"]
	pierce = caster.get("bullets_pierce") == true
	# Only damage-dealing spells declare one; get() keeps this agnostic of subclass.
	damage = spell.get("damage")

func _stat(key: String) -> int:
	var value = caster.get(key)
	return int(value) if value != null else 0

## Spawn one BaseBullet along `direction` from `position`, stamped with this
## cast's faction, stats and pierce. Pass deferred=true when spawning from an
## effect's own _ready (the tree is still busy adding the effect); a burst tick
## in _physics_process adds synchronously.
func spawn_bullet(bullet: BulletResource, direction: Vector2, position: Vector2, target: Node2D = null, deferred: bool = false) -> BaseBullet:
	var b: BaseBullet = _BulletScene.instantiate()
	b.data = bullet
	b.damage = damage
	b.collision_layer = bullet_layer
	b.base_direction = direction
	b.position = position
	b.skill = skill
	b.speed = speed
	b.defence = defence
	b.pierce = pierce
	b.target = target
	b.target_groups = target_groups
	if deferred:
		caster.get_tree().root.add_child.call_deferred(b)
	else:
		caster.get_tree().root.add_child(b)
	return b

## Nearest hostile within `range_px` and `cone_deg` of the aim direction, across
## every target group — the shared homing lock (no cursor position).
func find_target(direction: Vector2, range_px: float, cone_deg: float) -> Node2D:
	var from: Vector2 = caster.global_position  # live: a burst tracks the moving caster
	var best: Node2D = null
	for group in target_groups:
		var hit := AimAssist.nearest_in_cone(caster.get_tree(), group, from, direction, range_px, cone_deg)
		if hit and (best == null or from.distance_squared_to(hit.global_position) \
				< from.distance_squared_to(best.global_position)):
			best = hit
	return best
