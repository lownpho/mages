extends Node2D

## Whumf: lays a field of spore clouds around the caster and gets out of the way. The cast
## is over the moment they're down — everything after it belongs to the clouds.

const CLOUD := preload("res://characters/player/spells/whumf/spore_cloud.tscn")

const COUNT := 6           ## Clouds in the ring; one more always lands under the caster.
const SPREAD_TILES := 1.6  ## Under two tiles, so the ring overlaps into one field.

var data: WhumfResource
var ctx: CastContext

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	ctx = CastContext.new(spell, caster)

func _ready() -> void:
	var spread := SPREAD_TILES * GameConstants.PX_PER_TILE
	for i in COUNT + 1:
		var cloud: SporeCloud = CLOUD.instantiate()
		# One under the caster, the rest ringed around — Whumf lays spores AROUND you, and
		# the centre one is what makes the field solid rather than a donut.
		cloud.position = ctx.origin if i == 0 else ctx.origin + \
			Vector2(spread, 0).rotated(TAU * (i - 1) / COUNT)
		cloud.lifetime = data.cloud_lifetime
		cloud.tick_damage = data.tick_damage.compute(ctx.skill, ctx.speed, ctx.defence)
		cloud.blast_damage = data.blast_damage.compute(ctx.skill, ctx.speed, ctx.defence)
		cloud.target_groups = ctx.target_groups
		cloud.foe = ctx.bullet_layer != GameConstants.LAYER_PLAYER_BULLETS
		# Deferred: a direct add_child to root fails while our own _ready is still busy
		# adding us to the tree.
		get_tree().root.add_child.call_deferred(cloud)
	queue_free()
