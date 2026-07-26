extends BulletSpell

## ChargeDash: the caster is the projectile. Everything about the shots — the FlankPattern,
## the cadence, the length of the trail — is the bullet-spell engine underneath, unchanged.
## The one thing this adds is the run itself: the caster is driven along the cast's aim for
## dash_duration through start_dash, a capability both the player and Creature expose, so the
## same spell is a mobility burst in the player's hands and a boar's charge in a thornback's.
##
## The heading is locked at launch by construction — start_dash takes a direction, not a
## target — which is what makes a charge something you sidestep rather than outrun.

func _ready() -> void:
	super()
	var charge := data as ChargeDashResource
	if charge and caster.has_method("start_dash"):
		caster.start_dash(ctx.aim, charge.dash_speed, charge.dash_duration)
