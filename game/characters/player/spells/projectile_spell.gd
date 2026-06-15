extends Node2D

## Generic projectile-spell effect: spawns one BaseBullet from the spell's
## BulletResource, aimed at the cursor, then frees itself. Every behaviour —
## ricochet, homing, detonating into an AoE + ring — lives on the bullet, so this
## one effect drives Zoing (a ricochet bullet), Sploom (a homing bullet that
## explodes into a RingPattern), and any future projectile spell with no new code.
##
## Like a weapon, but triggered by the spell pipeline. Aim and the player-bullet
## layer are still player-coupled (the mouse, the "enemies" group) the way every
## other spell is; generalising that to enemies is the separate aim/faction step.

const _BulletScene = preload("res://items/bullets/base_bullet.tscn")

var data: ProjectileSpellResource
var skill: int = 0

var _direction: Vector2 = Vector2.RIGHT
var _aim_point: Vector2 = Vector2.ZERO

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	skill = caster.skill
	global_position = caster.global_position
	_aim_point = caster.get_global_mouse_position()
	_direction = (_aim_point - caster.global_position).normalized()
	if _direction == Vector2.ZERO:
		_direction = Vector2.RIGHT

func _ready() -> void:
	var bullet = _BulletScene.instantiate()
	bullet.data = data.bullet
	bullet.collision_layer = GameConstants.LAYER_PLAYER_BULLETS
	bullet.base_direction = _direction
	bullet.skill = skill
	bullet.position = global_position
	if data.bullet.homing:
		bullet.target = _nearest_enemy()
	# Deferred: spawned during our own _ready, while the tree is still adding us.
	get_tree().root.add_child.call_deferred(bullet)
	queue_free()

# Nearest enemy to the cursor, within the bullet's aim radius. Aiming at empty
# space locks nothing, so the bullet flies straight in the cast direction.
func _nearest_enemy() -> Node2D:
	var aim_px: float = data.bullet.homing_aim_tiles * GameConstants.PX_PER_TILE
	var best_d: float = aim_px * aim_px
	var best: Node2D = null
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.is_queued_for_deletion():
			continue
		var d: float = _aim_point.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best
