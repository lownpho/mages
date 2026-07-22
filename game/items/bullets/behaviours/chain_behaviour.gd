extends BulletBehaviour
class_name ChainBehaviour

## Lightning-chain: the bullet flies straight until it first zaps an enemy, then
## after each hit it leaps to the nearest hostile (excluding the one it's just
## leaving, so it can double back) until it runs out of hits or targets. Damage
## lands through each Hurtbox like any bullet; the chain only decides where to go
## next. Dies on walls (no on_expire payload). This is zaap, as data.

## Hits after the first: the chain reaches up to 1 + bounces enemies.
@export var bounces: int = 3
## Max leap distance to the next enemy in the chain, in tiles.
@export var bounce_range_tiles: float = 6.0

func on_ready(bullet: BaseBullet) -> void:
	bullet.runtime[self] = {"hits": 1 + bounces, "target": null, "last": null}

func on_step(bullet: BaseBullet, _delta: float) -> void:
	var st: Dictionary = bullet.runtime[self]
	var target = st["target"]
	if target == null:
		return  # still on the initial straight leg
	if not is_instance_valid(target):
		if not _retarget(bullet, bullet.global_position):  # target died mid-leap
			bullet.expire()
		return
	bullet.velocity = bullet.global_position.direction_to(target.global_position) * bullet.speed_px()
	bullet.face_velocity()

# Called after the hurtbox already took its damage; decide the next hop.
func on_hurtbox(bullet: BaseBullet) -> bool:
	var st: Dictionary = bullet.runtime[self]
	st["hits"] -= 1
	var victim := _nearest(bullet, null, bullet.global_position, 3.0 * GameConstants.PX_PER_TILE)
	if victim:
		st["last"] = victim
	if st["hits"] <= 0:
		return false  # spent — let the bullet expire
	return _retarget(bullet, victim.global_position if victim else bullet.global_position)

func _retarget(bullet: BaseBullet, from: Vector2) -> bool:
	var st: Dictionary = bullet.runtime[self]
	# Exclude only the enemy just zapped, so the chain can't instantly re-trigger
	# its own hurtbox — but it's free to loop back later. Drop a freed reference
	# first: a zapped enemy can die before the next hop, and a freed instance
	# fails _nearest's typed Node2D parameter.
	var last = st["last"] if is_instance_valid(st["last"]) else null
	var next := _nearest(bullet, last, from, bounce_range_tiles * GameConstants.PX_PER_TILE)
	if next == null:
		st["target"] = null
		return false
	st["target"] = next
	# Fresh leg bound, with slack for the target moving away.
	bullet.restart_leg(2.0 * bounce_range_tiles / bullet.data.speed_tiles)
	return true

# Nearest hostile across the bullet's target groups, excluding one enemy — the
# chain re-targets by proximity, not aim, so it can't reuse cone math.
func _nearest(bullet: BaseBullet, exclude: Node2D, from: Vector2, max_range_px: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_range_px * max_range_px
	for group in bullet.target_groups:
		for enemy in bullet.get_tree().get_nodes_in_group(group):
			if enemy == exclude or enemy.is_queued_for_deletion():
				continue
			var d: float = from.distance_squared_to(enemy.global_position)
			if d < best_d:
				best_d = d
				best = enemy
	return best
