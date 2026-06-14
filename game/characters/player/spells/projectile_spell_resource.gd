extends SpellResource
class_name ProjectileSpellResource

## A spell that fires one BaseBullet aimed at the cursor. All behaviour lives on
## the bullet's BulletResource — speed, homing, ricochet (wall_bounces), and the
## explode-on-expire payload (AoE blast + burst spray) — so this is the spell-side
## counterpart to a weapon: anything a weapon can fire, a spell can too, and the
## same data is reusable by enemies once spell aim/faction is generalised.
##
## The bullet carries the damage (base_damage/skill_scaling on the BulletResource),
## so the SpellResource's own damage fields are unused here.
@export var bullet: BulletResource
