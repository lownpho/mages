extends BulletSpell

## ChargeDash: the caster is the projectile. The shots are the bullet-spell engine
## underneath, unchanged; the one thing this adds is the run, driven through start_dash
## (both the player and Creature expose it). start_dash takes a direction, not a target,
## so the heading locks at launch — a charge is something you sidestep, not outrun.
##
## A spell with `contact_damage` also hangs a DamageZone on the caster for the run, so
## going straight through someone hits them once. It comes off when the dash ends (on a
## caster that exposes is_dashing) or when the burst does, whichever is first.

var _contact: DamageZone

func _ready() -> void:
	super()
	var charge := data as ChargeDashResource
	if not charge or not caster.has_method("start_dash"):
		return
	caster.start_dash(ctx.aim, charge.dash_speed, charge.dash_duration)
	if charge.contact_damage:
		_contact = _make_contact(charge)
		# Deferred: the wind-up can resolve from inside the caster's own physics step.
		caster.add_child.call_deferred(_contact)

func _physics_process(delta: float) -> void:
	if is_instance_valid(_contact) and is_instance_valid(caster) \
			and caster.has_method("is_dashing") and not caster.is_dashing():
		_contact.queue_free()
	super(delta)

func _exit_tree() -> void:
	if is_instance_valid(_contact):
		_contact.queue_free()

func _make_contact(charge: ChargeDashResource) -> DamageZone:
	var zone := DamageZone.new()
	zone.damage = charge.contact_damage.compute(ctx.skill, ctx.speed, ctx.defence)
	zone.weakness = ctx.weakness
	zone.collision_layer = ctx.bullet_layer
	zone.collision_mask = 0
	zone.monitoring = false
	var circle := CircleShape2D.new()
	circle.radius = charge.contact_radius_tiles * GameConstants.PX_PER_TILE
	var shape := CollisionShape2D.new()
	shape.shape = circle
	zone.add_child(shape)
	return zone
