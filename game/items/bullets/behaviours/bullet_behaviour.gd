extends Resource
class_name BulletBehaviour

## One composable trait of a bullet, mirroring FirePattern: a BulletResource
## carries an Array[BulletBehaviour] and BaseBullet dispatches these hooks to
## each. Behaviours are shared (one instance per resource, flown by many
## bullets), so they hold config only — per-bullet state lives in BaseBullet's
## `runtime` scratch dict, keyed by the behaviour. Override just the hooks a
## trait needs.

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

## The bullet is despawning (wall, range, or an unconsumed hurtbox): fire any
## payload (an AoE blast, a spray) here.
func on_expire(_bullet: BaseBullet) -> void:
	pass

## True if this trait suppresses the bullet's contact damage (a blast_only bomb
## deals only through its payload, so a direct and a splash hit match).
func suppresses_contact() -> bool:
	return false
