extends CharacterBody2D
class_name BaseBullet

## A projectile driven entirely by its BulletResource: kinematics here, every
## trait beyond flying straight delegated to the resource's BulletBehaviours.
## Set up by CastContext.spawn_bullet before the bullet enters the tree.
var data: BulletResource
## What this shot hits for. Comes from the CAST, not the shape — stamped by
## CastContext.spawn_bullet — so the same def fires for 20 from the player and 8
## from an enemy. null = a bullet that deals no damage of its own.
var damage: ScalingProfile
var base_direction: Vector2 = Vector2.UP
var target: Node2D  ## Homing lock, set by the firing effect. null = fly straight.
var skill: int = 0
var speed: int = 0  ## caster speed stat, for damage.speed_scaling (0 on enemy bullets)
var defence: int = 0  ## caster defence stat, for damage.defence_scaling (0 on enemy bullets)
var target_groups: Array = []  ## caster's hostiles, for behaviours that seek (chain)
## Pass through hurtboxes instead of despawning on contact (Clang buff). Leaves
## the "bullets" group so Hurtbox damages but never calls reached_hurtbox().
var pierce: bool = false

## How far the bullet has flown — behaviours (homing range) read this.
var distance_travelled: float = 0.0
## Per-bullet scratch for behaviours, keyed by the behaviour instance (which is
## shared across bullets, so it can't hold state itself).
var runtime: Dictionary = {}

var lifetime_timer: Timer
var _deals_contact_damage: bool = true

func speed_px() -> float:
	return data.speed_tiles * GameConstants.PX_PER_TILE

## Point the sprite along the current velocity — behaviours call this after they
## re-steer.
func face_velocity() -> void:
	rotation = velocity.angle() + PI / 2

## Restart the flight-leg timer (a behaviour re-arming its range after a hop);
## wait <= 0 reuses the current leg length.
func restart_leg(wait: float = -1.0) -> void:
	lifetime_timer.start(wait if wait > 0.0 else lifetime_timer.wait_time)

func _ready() -> void:
	# A bullet with no forward speed or no range can't travel — it would also make
	# the lifetime (range / speed) zero or divide by zero, which is an invalid
	# Timer.wait_time. Discard it rather than spawn a degenerate bullet.
	var lifetime := float(data.range_tiles) / data.speed_tiles if data.speed_tiles > 0 else 0.0
	if lifetime <= 0.0:
		queue_free()
		return

	if pierce:
		remove_from_group("bullets")
	# Enemy bullets also collide with spell barriers (Fwoosh's fire wall); player
	# bullets don't mask that layer, so the wall is one-way by construction.
	if collision_layer & GameConstants.LAYER_ENEMY_BULLETS:
		collision_mask |= GameConstants.LAYER_SPELL_BARRIER

	for b in data.behaviours:
		if b.suppresses_contact():
			_deals_contact_damage = false
		b.on_ready(self)

	lifetime_timer = Timer.new()
	lifetime_timer.one_shot = true
	lifetime_timer.wait_time = lifetime
	lifetime_timer.autostart = true
	lifetime_timer.timeout.connect(_expire)
	add_child(lifetime_timer)

	velocity = base_direction * speed_px()
	face_velocity()

	if data.icon:
		$Sprite2D.texture = data.icon

func _physics_process(delta: float) -> void:
	for b in data.behaviours:
		b.on_step(self, delta)

	# Terrain is the only thing in a bullet's collision mask, so a collision is
	# always a wall — the bullet expires (firing any on-expire payload).
	var motion := velocity * delta
	var collision := move_and_collide(motion)
	distance_travelled += motion.length()
	if collision:
		_expire()

func computed_damage() -> int:
	return damage.compute(skill, speed, defence) if damage else 0

func get_damage() -> int:
	# A blast_only bomb deals nothing on contact — the expire blast carries it all.
	return computed_damage() if _deals_contact_damage else 0

func reached_hurtbox() -> void:
	# Give behaviours first refusal (a chain consumes the hit and re-targets);
	# otherwise the bullet expires as usual.
	for b in data.behaviours:
		if b.on_hurtbox(self):
			return
	_expire()

## Force the bullet to despawn now, firing its on-expire payloads — a behaviour
## calls this when it dead-ends (e.g. a chain with no next target).
func expire() -> void:
	_expire()

# Single despawn path: fire every on-expire payload, then free. A plain bullet
# has no behaviours and just frees.
func _expire() -> void:
	for b in data.behaviours:
		b.on_expire(self)
	queue_free()
