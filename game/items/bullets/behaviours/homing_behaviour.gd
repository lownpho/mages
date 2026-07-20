extends BulletBehaviour
class_name HomingBehaviour

## Aim-assist steering toward the bullet's locked target (set at spawn by the
## firing effect's find_target). Steers only while within homing range, then
## flies straight.

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

func on_step(bullet: BaseBullet, delta: float) -> void:
	if is_instance_valid(bullet.target) and bullet.distance_travelled < bullet.runtime[self]:
		bullet.velocity = AimAssist.steer(bullet.velocity, bullet.global_position,
			bullet.target.global_position, turn_deg, cone_deg, delta)
		bullet.face_velocity()
