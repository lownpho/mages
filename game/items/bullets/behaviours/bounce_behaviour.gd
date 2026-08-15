extends BulletBehaviour
class_name BounceBehaviour

## Ricochet: instead of dying on a wall the bullet reflects and flies on, up to `bounces`
## times. Each reflection is a fresh leg of travel (the range timer restarts, so the shot
## gets its full range again per leg) and optionally hits harder than the last. Zoing.

## Wall hits the bullet survives; the one after this expires it as usual.
@export var bounces: int = 2
## Damage added per bounce, as a fraction of the shot's base — 0.5 means the second
## leg hits for 1.5x, the third for 2x. 0 = every leg hits the same.
@export var damage_per_bounce: float = 0.0

func on_ready(bullet: BaseBullet) -> void:
	bullet.runtime[self] = bounces

func on_wall(bullet: BaseBullet, collision: KinematicCollision2D) -> bool:
	if bullet.runtime[self] <= 0:
		return false
	bullet.runtime[self] -= 1
	bullet.velocity = bullet.velocity.bounce(collision.get_normal())
	# move_and_collide leaves the bullet flush against the surface; without nudging it
	# clear along the normal the very next sweep starts inside the wall and re-collides,
	# burning every bounce in a couple of frames.
	bullet.global_position += collision.get_normal() * _SKIN
	bullet.face_velocity()
	bullet.damage_scale += damage_per_bounce
	bullet.restart_leg()
	return true

# Enough to clear the collision margin without visibly teleporting the shot.
const _SKIN := 1.0
