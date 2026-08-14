extends BulletSpellResource
class_name MineResource

## A mine is a bullet spell that waits in the ground: everything about what it does when it
## goes off — pattern, bullet, damage — is the bullet-spell data underneath, and these two
## dials are the wait around it. Oop's single blast bullet and Ploop's ring of piercing
## darts are the same effect with different burst data.

@export_group("Mine")
## Seconds before it becomes live. A mine dropped under a chasing enemy shouldn't go off in
## its face — the delay is what makes it a placement rather than an attack.
@export var arm_time: float = 0.6
## Seconds it sits there before it rots away. 0 = it waits forever.
@export var lifetime: float = 12.0
