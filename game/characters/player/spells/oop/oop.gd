extends BulletSpell

## Oop: the caster IS the payload. Everything about the blast is the ordinary bullet-spell
## engine — a BlastPayload bullet like any other explosion — plus the one thing that makes
## it a self-detonation: once the burst is out, it takes the caster with it. Faction-agnostic
## like every other spell, so anything that can die can carry it.

func _ready() -> void:
	super()
	finished.connect(func() -> void:
		if is_instance_valid(caster) and caster.has_method("die"):
			caster.die())
