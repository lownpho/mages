extends Area2D
class_name DamageZone

## Area counterpart of a bullet body: a Hurtbox that overlaps this zone takes
## `damage` once on entry. Used by spell AoEs (explosions, bursts, beams), and by
## a body whose whole attack is running you over — a rollcap carries one instead
## of a caster, which is how "contact" is an attack with no spell behind it.

@export var damage: int = 0
## Kinds this zone doubles against, inherited from whatever spawned it (a bullet's blast).
## Left at 0 by a body whose contact IS its attack — a rollcap weakness nothing.
var weakness: int = 0

func get_damage() -> int:
	return damage
