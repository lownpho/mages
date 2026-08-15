extends BulletBehaviour
class_name HomingBehaviour

## Aim-assist steering toward the nearest hostile in the bullet's own cone,
## locked once at spawn. Steers only while within homing range, then flies
## straight.

## Max steering rate in degrees/second. Low (~120) nudges; ~1000+ snaps on.
@export var turn_deg: float = 360.0
## Assist engages only while the target sits within this angle of the heading,
## fading to zero at the edge. Also the cone the effect uses to lock a target.
## 180 = always steer (full homing).
@export var cone_deg: float = 60.0
## Tiles the bullet steers before flying straight. 0 = a default fraction of the
## bullet's range.
@export var range_tiles: float = 0.0

const _DEFAULT_FRACTION := 0.6

func on_ready(bullet: BaseBullet) -> void:
	var tiles := range_tiles if range_tiles > 0.0 \
		else bullet.data.range_tiles * _DEFAULT_FRACTION
	bullet.runtime[self] = tiles * GameConstants.PX_PER_TILE
	if bullet.target == null:
		bullet.target = _lock(bullet)

# Nearest hostile within the bullet's full range and this cone, across every
# target group — the lock the firing effect used to hand down.
func _lock(bullet: BaseBullet) -> Node2D:
	var from := bullet.global_position
	var range_px := bullet.data.range_tiles * GameConstants.PX_PER_TILE
	var best: Node2D = null
	for group in bullet.target_groups:
		var hit := AimAssist.nearest_in_cone(bullet.get_tree(), group, from,
			bullet.base_direction, range_px, cone_deg)
		if hit and (best == null or from.distance_squared_to(hit.global_position) \
				< from.distance_squared_to(best.global_position)):
			best = hit
	return best

func on_step(bullet: BaseBullet, delta: float) -> void:
	if is_instance_valid(bullet.target) and bullet.distance_travelled < bullet.runtime[self]:
		bullet.velocity = AimAssist.steer(bullet.velocity, bullet.global_position,
			bullet.target.global_position, turn_deg, cone_deg, delta)
		bullet.face_velocity()
