extends Node2D

## Kaboom volley spawner: scatters impact points very loosely around the cursor
## captured when the cast begins (effect_at_cast_start), drops one meteor on
## each, then frees itself — every meteor marks its point on the ground during
## the wind-up, falls, and explodes on its own. Damage is per meteor.

const _MeteorScene = preload("res://characters/player/spells/kaboom/kaboom_meteor.tscn")

var data: KaboomResource
var skill: int = 0

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	skill = caster.skill
	global_position = caster.get_global_mouse_position()

func _ready() -> void:
	var damage := roundi(data.base_damage + skill * data.skill_scaling)
	var radius := data.scatter_radius_tiles * GameConstants.PX_PER_TILE
	for i in data.meteor_count:
		var meteor = _MeteorScene.instantiate()
		meteor.damage = damage
		meteor.mark_texture = data.mark_texture
		meteor.explosion_frames = data.explosion_frames
		meteor.aoe_tiles = data.aoe_tiles
		meteor.impact_delay = data.impact_delay + randf() * data.impact_jitter
		# sqrt for a uniform scatter over the disc, not bunched at the center
		meteor.position = global_position + Vector2(sqrt(randf()) * radius, 0).rotated(randf() * TAU)
		# Deferred: this runs during our own _ready, while the tree is still
		# busy adding us — a direct add_child to root fails there.
		get_tree().root.add_child.call_deferred(meteor)
	queue_free()
