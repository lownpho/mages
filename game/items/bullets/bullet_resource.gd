extends Resource
class_name BulletResource

## A projectile SHAPE for base_bullet.tscn: how the bullet looks and moves, plus a
## list of composable BulletBehaviours (homing, chain, blast…) that add everything
## beyond flying straight. The bullet itself carries no bespoke behaviour — traits
## are data, so a new kind of bullet is a new mix of behaviours, not a new field here.
##
## Carries NO damage: power belongs to the cast (BulletSpellResource.damage), so the
## same projectile can hit for one number when the player fires it and another when an
## enemy does. Each spell authors its own bullet inline — a spell is one self-contained
## file — so retuning one caster's shot never reaches into anyone else's.

@export var icon: Texture2D
@export var range_tiles: int = 16
@export var speed_tiles: int = 128
## Composable traits (see BulletBehaviour): homing steer, chain, on-expire blast.
## Empty = a plain bullet that flies straight and dies on wall/range/hit.
@export var behaviours: Array[BulletBehaviour] = []

## First homing trait, if any — the firing effect reads it to lock a target and
## its cone. null = the bullet doesn't home.
func homing() -> HomingBehaviour:
	for b in behaviours:
		if b is HomingBehaviour:
			return b
	return null
