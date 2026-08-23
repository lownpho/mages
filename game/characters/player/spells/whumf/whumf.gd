extends Node2D

## Whumf: lays a field of spore clouds around the caster and gets out of the way. The cast
## is over the moment they're down — everything after it belongs to the clouds.

const CLOUD := preload("res://characters/player/spells/whumf/spore_cloud.tscn")

var data: WhumfResource
var ctx: CastContext

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	ctx = CastContext.new(spell, caster)

func _ready() -> void:
	var spread := data.spread_tiles * GameConstants.PX_PER_TILE
	for i in data.ring_clouds + 1:
		var cloud: SporeCloud = CLOUD.instantiate()
		# One under the caster, the rest ringed around — Whumf lays spores AROUND you, and
		# the centre one is what makes the field solid rather than a donut.
		cloud.position = ctx.origin if i == 0 else ctx.origin + \
			Vector2(spread, 0).rotated(TAU * (i - 1) / data.ring_clouds)
		cloud.lifetime = data.cloud_lifetime
		# Left unset by every enemy cast: the dungeon's spores all hurt the same, and that
		# number is SporeCloud's own.
		if data.tick_damage:
			cloud.tick_damage = data.tick_damage.compute(ctx.skill, ctx.speed, ctx.defence)
		if data.blast_damage:
			cloud.blast_damage = data.blast_damage.compute(ctx.skill, ctx.speed, ctx.defence)
		cloud.target_groups = ctx.target_groups
		cloud.foe = ctx.bullet_layer != GameConstants.LAYER_PLAYER_BULLETS
		# Deferred: a direct add_child to root fails while our own _ready is still busy
		# adding us to the tree.
		get_tree().root.add_child.call_deferred(cloud)
	# A mine is its own payload: the spores are down, so there is nothing left of it.
	if data.consumes_caster and is_instance_valid(ctx.caster) and ctx.caster.has_method("die"):
		ctx.caster.die()
	queue_free()
