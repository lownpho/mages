extends Area2D
class_name DamageZone

## Area counterpart of a bullet body: a Hurtbox that overlaps this zone takes
## `damage` once on entry. Used by spell AoEs (explosions, bursts, beams).

var damage: int = 0

func get_damage() -> int:
	return damage
