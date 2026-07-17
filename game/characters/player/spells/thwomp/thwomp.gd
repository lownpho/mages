extends Node2D

## Thwomp: an instant radial pulse centred on the caster. Damage lands through a
## DamageZone (flat, like any AoE), and every hostile in range is shoved outward
## with a distance-falloff impulse via Creature.apply_knockback — faction-agnostic
## (the damage layer and the pushed groups both come from the caster). Scales with
## the caster's defence stat (a close-range "get off me" tool).

const DamageZoneScript = preload("res://components/damage_zone.gd")

var data: ThwompResource
var _caster: Node2D
var skill: int = 0
var caster_defence: int = 0

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	_caster = caster
	skill = caster.skill
	var dfc = caster.get("defence")
	caster_defence = dfc if dfc != null else 0
	global_position = caster.global_position

func _ready() -> void:
	var radius := data.radius_tiles * GameConstants.PX_PER_TILE
	var layer_override = _caster.get("bullet_collision_layer")
	var layer: int = layer_override if layer_override != null else GameConstants.LAYER_PLAYER_BULLETS

	# Flat AoE damage through the standard channel.
	var zone := DamageZoneScript.new()
	zone.damage = data.damage_for(skill, 0, caster_defence)
	zone.collision_layer = layer
	zone.collision_mask = 0
	zone.monitoring = false
	zone.position = global_position
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	zone.add_child(shape)
	var life := Timer.new()
	life.one_shot = true
	life.autostart = true
	life.wait_time = 0.1
	life.timeout.connect(zone.queue_free)
	zone.add_child(life)
	get_tree().root.add_child.call_deferred(zone)

	# Knockback with distance falloff, on whatever this caster hunts.
	var groups = _caster.get("target_groups")
	if groups == null:
		groups = ["enemies"]
	for group in groups:
		for node in get_tree().get_nodes_in_group(group):
			if not node.has_method("apply_knockback"):
				continue
			var offset: Vector2 = node.global_position - global_position
			var dist := offset.length()
			if dist > radius:
				continue
			var falloff := 1.0 - dist / radius
			var dir := offset.normalized() if dist > 0.01 else Vector2.RIGHT
			node.apply_knockback(dir * data.knockback_force * falloff)

	queue_free()
