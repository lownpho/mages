extends CharacterBody2D

## Sploom bomb: a slow, heavily homing projectile. On reaching an enemy, a wall,
## or its max range it detonates — a central AoE blast (a DamageZone) plus an even
## ring of bullets flying outward. Fire-and-forget: it curves hard onto the nearest
## enemy, so the launch aim barely matters.

const _BulletScene = preload("res://items/bullets/base_bullet.tscn")

var data: SploomResource
var skill: int = 0

var _direction: Vector2 = Vector2.RIGHT
var _detonated: bool = false

@onready var blast: DamageZone = $Blast

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	skill = caster.skill
	global_position = caster.global_position
	_direction = (caster.get_global_mouse_position() - caster.global_position).normalized()
	if _direction == Vector2.ZERO:
		_direction = Vector2.RIGHT

func _ready() -> void:
	if data.projectile_texture:
		$Sprite2D.texture = data.projectile_texture
	velocity = _direction * _speed()

	blast.damage = roundi(data.base_damage + skill * data.skill_scaling)
	var shape := CircleShape2D.new()
	shape.radius = data.aoe_tiles * GameConstants.PX_PER_TILE / 2.0
	$Blast/CollisionShape2D.shape = shape

	# Detonate at max range if it never reaches an enemy or wall.
	var range_timer := Timer.new()
	range_timer.one_shot = true
	range_timer.autostart = true
	range_timer.wait_time = data.range_tiles / data.speed_tiles
	range_timer.timeout.connect(_detonate)
	add_child(range_timer)

func _speed() -> float:
	return data.speed_tiles * GameConstants.PX_PER_TILE

func _physics_process(delta: float) -> void:
	if _detonated:
		return
	var target := _nearest_enemy()
	if target:
		var speed := _speed()
		var desired := global_position.direction_to(target.global_position)
		velocity = velocity.lerp(desired * speed, data.homing_weight * delta).normalized() * speed
	rotation = velocity.angle() + PI / 2
	if move_and_collide(velocity * delta):
		_detonate()

func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	$Sprite2D.hide()
	$CollisionShape2D.set_deferred("disabled", true)
	$Blast/CollisionShape2D.set_deferred("disabled", false)

	if data.ring_bullet:
		for i in data.ring_bullets:
			var dir := Vector2.RIGHT.rotated(TAU * i / data.ring_bullets)
			var bullet = _BulletScene.instantiate()
			bullet.data = data.ring_bullet
			bullet.collision_layer = GameConstants.LAYER_PLAYER_BULLETS
			bullet.base_direction = dir
			bullet.skill = skill
			bullet.position = global_position
			# Deferred: spawned during our own _detonate, the tree may be busy.
			get_tree().root.add_child.call_deferred(bullet)

	# Let the blast register overlaps for a beat, then clean up.
	var life := Timer.new()
	life.one_shot = true
	life.autostart = true
	life.wait_time = 0.1
	life.timeout.connect(queue_free)
	add_child(life)

func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var range_px := data.range_tiles * GameConstants.PX_PER_TILE
	var best_d := range_px * range_px
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.is_queued_for_deletion():
			continue
		var d: float = global_position.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best
