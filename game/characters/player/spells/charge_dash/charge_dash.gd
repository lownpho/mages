extends BulletSpell

## ChargeDash: the caster is the projectile. The shots are the bullet-spell engine
## underneath, unchanged; the one thing this adds is the run, driven through start_dash
## (both the player and Creature expose it). start_dash takes a direction, not a target,
## so the heading locks at launch — a charge is something you sidestep, not outrun.

func _ready() -> void:
	super()
	var charge := data as ChargeDashResource
	if charge and caster.has_method("start_dash"):
		caster.start_dash(ctx.aim, charge.dash_speed, charge.dash_duration)
