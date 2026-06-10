extends Node2D

## Piercing Lights volley spawner: scatters the lights around the caster, all
## flying toward the cursor captured when the cast resolves, then frees itself
## — each light lives on its own. Damage is per projectile.

const _LightScene = preload("res://characters/player/spells/piercing_lights/piercing_light.tscn")

var data: PiercingLightsResource
var skill: int = 0

var _direction: Vector2 = Vector2.RIGHT

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	skill = caster.skill
	global_position = caster.global_position
	_direction = (caster.get_global_mouse_position() - caster.global_position).normalized()

func _ready() -> void:
	var damage := roundi(data.base_damage + skill * data.skill_scaling)
	var speed := data.speed_tiles * GameConstants.PX_PER_TILE
	var radius := data.spawn_radius_tiles * GameConstants.PX_PER_TILE
	for i in data.projectile_count:
		var light = _LightScene.instantiate()
		light.damage = damage
		light.texture = data.projectile_texture
		# sqrt for a uniform scatter over the disc, not bunched at the center
		light.position = global_position + Vector2(sqrt(randf()) * radius, 0).rotated(randf() * TAU)
		light.velocity = _direction * speed
		light.rotation = _direction.angle() + PI / 2
		light.launch_delay = data.hang_time + i * data.launch_stagger
		# Deferred: this runs during our own _ready, while the tree is still
		# busy adding us — a direct add_child to root fails there.
		get_tree().root.add_child.call_deferred(light)
	queue_free()
