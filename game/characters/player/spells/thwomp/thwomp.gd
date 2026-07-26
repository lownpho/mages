extends Node2D

## Thwomp: an instant radial pulse centred on the caster — the "get off me" button, and the
## gnarlking's ground slam. One sweep over the caster's target groups does both halves of it,
## because both fall off with the same distance: the hit is full at the centre and chip at
## the rim, and the shove is an impulse through Creature.apply_knockback on the same curve.
##
## Faction-agnostic by construction: who it hits is CastContext.target_groups, so the player's
## panic button and a boss's slam are one file. Damage goes through each victim's own Hurtbox
## signal rather than a DamageZone — a zone carries ONE number for everyone inside it, which
## is exactly the thing a falloff pulse can't do.

var data: ThwompResource
var ctx: CastContext

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	ctx = CastContext.new(spell, caster)
	global_position = caster.global_position

func _ready() -> void:
	var radius := data.radius_tiles * GameConstants.PX_PER_TILE
	var full := ctx.damage.compute(ctx.skill, ctx.speed, ctx.defence) if ctx.damage else 0
	for group in ctx.target_groups:
		for node in get_tree().get_nodes_in_group(group):
			var offset: Vector2 = node.global_position - global_position
			var dist := offset.length()
			if dist > radius:
				continue
			# 1 at the centre, 0 at the rim — the curve both halves ride.
			var falloff := 1.0 - dist / radius
			_hit(node, roundi(full * lerpf(data.edge_damage, 1.0, falloff)))
			if node.has_method("apply_knockback"):
				var dir := offset.normalized() if dist > 0.01 else Vector2.RIGHT
				node.apply_knockback(dir * data.knockback_force * falloff)
	queue_free()

# The victim's own Hurtbox signal — the same one a bullet body reaches through — so shields,
# armour and the floating numbers all behave exactly as they do for any other hit.
func _hit(node: Node, amount: int) -> void:
	if amount <= 0:
		return
	var hurtbox = node.get("hurtbox")
	if hurtbox:
		hurtbox.hurt.emit(amount, self)
