extends CharacterBody2D
class_name BaseBullet

## All bullet stats are read from this resource — the single source of truth.
## Set by WeaponNode before the bullet enters the tree.
var data: BulletResource
var base_direction: Vector2 = Vector2.UP
var target: Node2D
var skill: int = 0
var speed: int = 0  ## caster speed stat, for data.speed_scaling (0 on enemy bullets)
## Pass through hurtboxes instead of despawning on contact (Clang buff). Leaves
## the "bullets" group so Hurtbox damages but never calls reached_hurtbox().
var pierce: bool = false

var lifetime_timer: Timer
var _bounces_left: int = 0
# How far the bullet steers before flying straight, and how far it has flown.
var _homing_range_px: float = 0.0
var _distance_travelled: float = 0.0

## Fraction of range_tiles a homing bullet steers for when the resource leaves
## homing_range_tiles at 0 — it locks on early, then flies straight to the target.
const _DEFAULT_HOMING_FRACTION := 0.6

func _speed() -> float:
	return data.speed_tiles * GameConstants.PX_PER_TILE

func _ready() -> void:
	# A bullet with no forward speed or no range can't travel — it would also make
	# the lifetime (range / speed) zero or divide by zero, which is an invalid
	# Timer.wait_time. Discard it rather than spawn a degenerate bullet.
	var lifetime := float(data.range_tiles) / data.speed_tiles if data.speed_tiles > 0 else 0.0
	if lifetime <= 0.0:
		queue_free()
		return

	_bounces_left = data.wall_bounces
	if pierce:
		remove_from_group("bullets")
	# Enemy bullets also collide with spell barriers (Fwoosh's fire wall); player
	# bullets don't mask that layer, so the wall is one-way by construction.
	if collision_layer & GameConstants.LAYER_ENEMY_BULLETS:
		collision_mask |= GameConstants.LAYER_SPELL_BARRIER

	var homing_tiles := data.homing_range_tiles if data.homing_range_tiles > 0.0 \
		else data.range_tiles * _DEFAULT_HOMING_FRACTION
	_homing_range_px = homing_tiles * GameConstants.PX_PER_TILE

	lifetime_timer = Timer.new()
	lifetime_timer.one_shot = true
	lifetime_timer.wait_time = lifetime
	lifetime_timer.autostart = true
	lifetime_timer.timeout.connect(_expire)
	add_child(lifetime_timer)

	velocity = base_direction * _speed()
	rotation = velocity.angle() + PI / 2

	if data.icon:
		$Sprite2D.texture = data.icon

func _physics_process(delta: float) -> void:
	# Aim assist (cone-gated steering — see AimAssist.steer), only within the
	# homing range; beyond it the bullet keeps its heading and flies straight.
	if data.homing and is_instance_valid(target) and _distance_travelled < _homing_range_px:
		velocity = AimAssist.steer(velocity, global_position, target.global_position,
			data.homing_turn_deg, data.homing_cone_deg, delta)
		rotation = velocity.angle() + PI / 2

	# Terrain is the only thing in a bullet's collision mask, so a collision is
	# always a wall. Ricochet if any bounces remain — the leg restarts so total
	# travel grows with bounces — otherwise expire.
	var motion := velocity * delta
	var collision := move_and_collide(motion)
	_distance_travelled += motion.length()
	if collision:
		if _bounces_left > 0:
			_bounces_left -= 1
			velocity = velocity.bounce(collision.get_normal())
			rotation = velocity.angle() + PI / 2
			lifetime_timer.start()
		else:
			_expire()

func get_damage() -> int:
	return round(data.base_damage + skill * data.skill_scaling + speed * data.speed_scaling)

func reached_hurtbox() -> void:
	_expire()

# Single despawn path. Fires the on-expire payload (AoE blast and/or burst spray)
# if the resource carries one, then frees. A plain bullet has no payload and just
# frees — identical to the old behaviour.
func _expire() -> void:
	if data.explode_radius_tiles > 0.0:
		_spawn_blast()
	if data.burst_pattern and data.burst_bullet:
		_spawn_burst()
	queue_free()

func _spawn_blast() -> void:
	var zone := DamageZone.new()
	zone.damage = get_damage()
	zone.collision_layer = collision_layer  # faction inherited from this bullet
	zone.collision_mask = 0
	zone.monitoring = false
	zone.position = global_position
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = data.explode_radius_tiles * GameConstants.PX_PER_TILE / 2.0
	shape.shape = circle
	zone.add_child(shape)
	# Brief life so hurtboxes register the overlap, then it cleans itself up.
	var life := Timer.new()
	life.one_shot = true
	life.autostart = true
	life.wait_time = 0.1
	life.timeout.connect(zone.queue_free)
	zone.add_child(life)
	# Deferred: _expire can run mid-collision while the tree is busy.
	get_tree().root.add_child.call_deferred(zone)

func _spawn_burst() -> void:
	var scene := load("res://items/bullets/base_bullet.tscn") as PackedScene
	var origin := global_position
	for dir in data.burst_pattern.get_directions(velocity.normalized()):
		var bullet = scene.instantiate()
		bullet.data = data.burst_bullet
		bullet.collision_layer = collision_layer  # faction inherited
		bullet.base_direction = dir
		bullet.skill = skill
		bullet.speed = speed
		bullet.position = origin
		get_tree().root.add_child.call_deferred(bullet)
