extends Resource
class_name BulletBehaviour

## One composable trait of a bullet: BaseBullet dispatches these hooks to every entry in
## its BulletResource's `behaviours`. Behaviours are SHARED (one instance per resource,
## flown by many bullets), so they hold config only — per-bullet state goes in
## BaseBullet's `runtime` scratch dict, keyed by the behaviour.

## Per-bullet setup: stash any runtime counters in `bullet.runtime`.
func on_ready(_bullet: BaseBullet) -> void:
	pass

## Per physics frame, before movement: steering lives here.
func on_step(_bullet: BaseBullet, _delta: float) -> void:
	pass

## The bullet reached a hurtbox. Return true to consume the hit (the bullet
## keeps flying — e.g. a chain re-targets); false lets it expire as usual.
func on_hurtbox(_bullet: BaseBullet) -> bool:
	return false

## The bullet hit a wall. Return true to consume the collision (the bullet keeps
## flying — e.g. a ricochet reflects it); false lets it expire as usual. The
## collision carries the surface normal a reflection needs.
func on_wall(_bullet: BaseBullet, _collision: KinematicCollision2D) -> bool:
	return false

## The bullet is despawning (wall, range, or an unconsumed hurtbox): fire any
## payload (an AoE blast, a spray) here.
func on_expire(_bullet: BaseBullet) -> void:
	pass

## True if this trait suppresses the bullet's contact damage (a blast_only bomb
## deals only through its payload, so a direct and a splash hit match).
func suppresses_contact() -> bool:
	return false
