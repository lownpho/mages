extends Resource
class_name BulletResource

## A projectile SHAPE for base_bullet.tscn: how the bullet looks and moves, plus the
## composable BulletBehaviours that add everything beyond flying straight. A new kind of
## bullet is a new mix of behaviours, never a new field here.
##
## Carries NO damage: power belongs to the cast (BulletSpellResource.damage), so the same
## projectile hits for one number in the player's hands and another in an enemy's.

@export var icon: Texture2D
@export var range_tiles: int = 16
@export var speed_tiles: int = 128
## Fly through hurtboxes instead of dying on the first one hit (Zoing). The caster's
## own pierce buff (Clang) ORs into this, so a shot pierces if either says so.
@export var pierce: bool = false
## Composable traits (see BulletBehaviour): homing steer, chain, on-expire blast.
## Empty = a plain bullet that flies straight and dies on wall/range/hit.
@export var behaviours: Array[BulletBehaviour] = []
