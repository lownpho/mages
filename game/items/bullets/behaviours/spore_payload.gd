extends BulletBehaviour
class_name SporePayload

## On-expire spore patch: wherever the shot stops — a body, a wall, the end of its range — it
## leaves a SporeCloud behind. This is how something rooted paints floor it isn't standing on,
## and it lands the same patch the player's Whumf lays, faction and all, so the Mycelium's
## floor is one primitive however it got there.
##
## The lob's own damage stays on its ScalingProfile (usually zero — the cloud is the point);
## these are the patch's numbers, flat, because only creatures lob spores and creature damage
## never scales.

const CLOUD := preload("res://characters/player/spells/whumf/spore_cloud.tscn")

@export var cloud_lifetime: float = 12.0
## Per half second, to whatever the shot's caster hunts.
@export var tick_damage: int = 1
## Only ever paid out if the PLAYER laid it: an enemy's field is inert terrain and nothing
## can light it (see SporeCloud.detonate).
@export var blast_damage: int = 0

func on_expire(bullet: BaseBullet) -> void:
	var cloud: SporeCloud = CLOUD.instantiate()
	cloud.position = bullet.global_position
	cloud.lifetime = cloud_lifetime
	cloud.tick_damage = tick_damage
	cloud.blast_damage = blast_damage
	cloud.target_groups = bullet.target_groups
	cloud.foe = bullet.collision_layer != GameConstants.LAYER_PLAYER_BULLETS
	# Deferred: on_expire can run mid-collision while the tree is busy.
	bullet.get_tree().root.add_child.call_deferred(cloud)
