extends Area2D
class_name DamageZone

## Area counterpart of a bullet body: a Hurtbox that overlaps this zone takes
## `damage` once on entry. Used by spell AoEs (explosions, bursts, beams), and by
## a body whose whole attack is running you over — a rollcap carries one instead
## of a caster, which is how "contact" is an attack with no spell behind it.

@export var damage: int = 0

func get_damage() -> int:
	return damage
