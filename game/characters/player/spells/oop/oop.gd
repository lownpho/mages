extends BulletSpell

## Oop: the caster IS the payload. The blast is an ordinary BlastPayload bullet; the one
## thing this adds is that once the burst is out, it takes the caster with it.

func _ready() -> void:
	super()
	finished.connect(func() -> void:
		if is_instance_valid(caster) and caster.has_method("die"):
			caster.die())
