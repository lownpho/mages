extends BulletBehaviour
class_name SporeDetonator

## Light is the one thing that sets a spore cloud off — fire deliberately doesn't, or
## Fireball would make every player a detonator by accident. A bullet carrying this lights
## any cloud it crosses and keeps flying: the match isn't spent on the fuse.
##
## Only your OWN spores light — SporeCloud.light owns that rule, and Blink's arrival flash
## goes through the same call.
##
## A marker behaviour rather than a flag on BulletResource, because a new kind of bullet is
## a new mix of behaviours.

func on_step(bullet: BaseBullet, _delta: float) -> void:
	SporeCloud.light(bullet.global_position, bullet.target_groups)
