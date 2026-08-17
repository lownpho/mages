extends BulletBehaviour
class_name SporeDetonator

## Light is the one thing that sets a spore cloud off — fire deliberately doesn't, or
## Fireball would make every player a detonator by accident. A bullet carrying this lights
## any cloud it crosses and keeps flying: the match isn't spent on the fuse.
##
## Only your OWN spores light (SporeCloud.detonate refuses the rest). An enemy's field is
## skipped rather than merely no-opped, so a match crossing the dungeon's floor on its way to
## your field still has a fuse to reach.
##
## A marker behaviour rather than a flag on BulletResource, because a new kind of bullet is
## a new mix of behaviours.

func on_step(bullet: BaseBullet, _delta: float) -> void:
	for cloud in bullet.get_tree().get_nodes_in_group(SporeCloud.GROUP):
		if cloud.foe:
			continue
		if cloud.covers(bullet.global_position):
			cloud.detonate(bullet.target_groups)
			return
