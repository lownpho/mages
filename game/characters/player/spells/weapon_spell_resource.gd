extends SpellResource
class_name WeaponSpellResource

## A weapon as a spell: casting looses a burst — the fire_pattern fired every
## shot_interval at the caster's aim direction — until max_shots are spent or
## burst_window elapses after the first shot, whichever comes first, then the
## spell goes on cooldown. The behaviour lives in the generic weapon_spell.tscn
## effect; a new weapon is one .tres composing a FirePattern and a
## BulletResource, no code.

@export_group("Weapon Spell")
@export var fire_pattern: FirePattern
@export var bullet: BulletResource
## Seconds between shots within the burst.
@export var shot_interval: float = 0.25
## Shots in one burst; the burst ends early if burst_window elapses first.
@export var max_shots: int = 6
## Seconds after the first shot before the burst force-ends. Keeps ticking while
## the burst is suspended (a cast or channel pauses firing, never cancels it).
@export var burst_window: float = 2.0

func get_stats() -> Array:
	var rows := []
	if bullet:
		rows.append(["damage", "%d" % int(bullet.base_damage)])
	rows.append(["cooldown", "%.1f" % cooldown])
	return rows
