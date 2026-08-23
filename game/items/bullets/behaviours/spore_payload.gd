extends BulletBehaviour
class_name SporePayload

## On-expire spore patch: wherever the shot stops — a body, a wall, the end of its range — it
## leaves a SporeCloud behind. This is how something rooted paints floor it isn't standing on,
## and it lands the same patch the player's Whumf lays, faction and all, so the Mycelium's
## floor is one primitive however it got there.
##
## The lob's own damage stays on its ScalingProfile (usually zero — the cloud is the point).
## The patch's damage isn't here at all: it's the dungeon's floor, so SporeCloud holds it.
## Only how long it lasts is this shot's business.

const CLOUD := preload("res://characters/player/spells/whumf/spore_cloud.tscn")

@export var cloud_lifetime: float = 30.0

func on_expire(bullet: BaseBullet) -> void:
	var cloud: SporeCloud = CLOUD.instantiate()
	cloud.position = bullet.global_position
	cloud.lifetime = cloud_lifetime
	cloud.target_groups = bullet.target_groups
	cloud.foe = bullet.collision_layer != GameConstants.LAYER_PLAYER_BULLETS
	# Deferred: on_expire can run mid-collision while the tree is busy.
	bullet.get_tree().root.add_child.call_deferred(cloud)
