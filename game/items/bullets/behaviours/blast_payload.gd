extends BulletBehaviour
class_name BlastPayload

## On-expire AoE: when the bullet dies (wall, range, or reaching a hurtbox) it
## spawns a one-shot damage zone of `radius_tiles` dealing the bullet's own
## damage, plus an optional animation. This is what makes an exploding bullet
## read as a fireball — no bespoke code.

@export var radius_tiles: float = 3.0
## One-shot animation played at the blast, sized to match (native resolution —
## never scaled). null = an invisible blast.
@export var frames: SpriteFrames
## Deal damage only through the blast, not on contact, so a direct and a splash
## hit are worth the same (a bomb). Suppresses the bullet's contact damage.
@export var blast_only: bool = false

func suppresses_contact() -> bool:
	return blast_only

func on_expire(bullet: BaseBullet) -> void:
	if frames:
		_spawn_vfx(bullet)
	var zone := DamageZone.new()
	zone.damage = bullet.computed_damage()
	zone.collision_layer = bullet.collision_layer  # faction inherited from the bullet
	zone.collision_mask = 0
	zone.monitoring = false
	zone.position = bullet.global_position
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius_tiles * GameConstants.PX_PER_TILE / 2.0
	shape.shape = circle
	zone.add_child(shape)
	# Brief life so hurtboxes register the overlap, then it cleans itself up.
	var life := Timer.new()
	life.one_shot = true
	life.autostart = true
	life.wait_time = 0.1
	life.timeout.connect(zone.queue_free)
	zone.add_child(life)
	# Deferred: on_expire can run mid-collision while the tree is busy.
	bullet.get_tree().root.add_child.call_deferred(zone)

# The blast's one-shot animation, at the impact point, freeing itself when done.
# Separate from the (0.1s) damage zone so it plays out its full length.
func _spawn_vfx(bullet: BaseBullet) -> void:
	var vfx := AnimatedSprite2D.new()
	vfx.sprite_frames = frames
	vfx.position = bullet.global_position
	var anim: StringName = frames.get_animation_names()[0]
	vfx.animation_finished.connect(vfx.queue_free)
	vfx.play(anim)
	bullet.get_tree().root.add_child.call_deferred(vfx)
