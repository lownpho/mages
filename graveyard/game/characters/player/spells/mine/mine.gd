extends Node2D

## Mine spawner + manager (Ploop / Oop). Drops MineResource.mine_count mines
## scattered around the caster; each arms after arm_delay, then detonates when a
## hostile enters trigger_radius, firing the data-driven payload (AoE blast and/or
## a dart burst) on the caster's bullet layer. Frees itself once no mines remain.
## Faction-agnostic: aim groups and bullet layer come from the caster.

const _BulletScene = preload("res://items/bullets/base_bullet.tscn")
const DamageZoneScript = preload("res://components/damage_zone.gd")

var data: MineResource
var _caster: Node2D
var skill: int = 0
var caster_speed: int = 0
var _layer: int = 0
var _groups: Array = ["enemies"]
var _mines: Array = []  # each: {node: Node2D, life: float}

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	_caster = caster
	skill = caster.skill
	var spd = caster.get("speed")
	caster_speed = spd if spd != null else 0
	global_position = caster.global_position

func _ready() -> void:
	var layer_override = _caster.get("bullet_collision_layer")
	_layer = layer_override if layer_override != null else GameConstants.LAYER_PLAYER_BULLETS
	var groups = _caster.get("target_groups")
	if groups != null:
		_groups = groups
	var scatter := data.scatter_tiles * GameConstants.PX_PER_TILE
	var tex: Texture2D = data.mine_texture if data.mine_texture else data.icon
	for i in data.mine_count:
		var m := Sprite2D.new()
		m.texture = tex
		m.position = Vector2(sqrt(randf()) * scatter, 0).rotated(randf() * TAU)
		add_child(m)
		_mines.append({"node": m, "life": 0.0})

func _physics_process(delta: float) -> void:
	var radius := data.trigger_radius_tiles * GameConstants.PX_PER_TILE
	for entry in _mines.duplicate():
		var m: Node2D = entry["node"]
		entry["life"] += delta
		if entry["life"] >= data.mine_lifetime:
			_mines.erase(entry)
			m.queue_free()
			continue
		if entry["life"] < data.arm_delay:
			continue
		var mine_pos: Vector2 = m.global_position
		if _hostile_within(mine_pos, radius):
			_detonate(mine_pos)
			_mines.erase(entry)
			m.queue_free()
	if _mines.is_empty():
		queue_free()

func _hostile_within(from: Vector2, radius: float) -> bool:
	var r2 := radius * radius
	for group in _groups:
		for node in get_tree().get_nodes_in_group(group):
			if from.distance_squared_to(node.global_position) <= r2:
				return true
	return false

func _detonate(pos: Vector2) -> void:
	var damage := data.damage_for(skill, caster_speed)
	if data.explode_radius_tiles > 0.0:
		var zone := DamageZoneScript.new()
		zone.damage = damage
		zone.collision_layer = _layer
		zone.collision_mask = 0
		zone.monitoring = false
		zone.global_position = pos
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = data.explode_radius_tiles * GameConstants.PX_PER_TILE / 2.0
		shape.shape = circle
		zone.add_child(shape)
		var life := Timer.new()
		life.one_shot = true
		life.autostart = true
		life.wait_time = 0.1
		life.timeout.connect(zone.queue_free)
		zone.add_child(life)
		get_tree().root.add_child.call_deferred(zone)
	if data.burst_pattern and data.burst_bullet:
		for dir in data.burst_pattern.get_directions(Vector2.RIGHT):
			var bullet = _BulletScene.instantiate()
			bullet.data = data.burst_bullet
			bullet.collision_layer = _layer
			bullet.base_direction = dir
			bullet.skill = skill
			bullet.speed = caster_speed
			bullet.pierce = true if data.explode_radius_tiles <= 0.0 else false
			bullet.global_position = pos
			get_tree().root.add_child.call_deferred(bullet)
