extends CharacterBody2D

## Zoing bolt: a fast bullet that ricochets off walls. Each wall bounce reflects
## the velocity and starts a fresh flight leg, so total travel grows with bounces.
## It's a single-hit bullet on enemies (in the "bullets" group, so the hurtbox
## despawns it); only walls bounce it. Dies when its bounces are spent or a leg
## expires without hitting a wall.

var data: ZoingResource
var skill: int = 0

var _direction: Vector2 = Vector2.RIGHT
var _bounces_left: int = 0
var _leg_timer: Timer

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	skill = caster.skill
	global_position = caster.global_position
	_direction = (caster.get_global_mouse_position() - caster.global_position).normalized()
	if _direction == Vector2.ZERO:
		_direction = Vector2.RIGHT

func _ready() -> void:
	_bounces_left = data.bounces
	if data.projectile_texture:
		$Sprite2D.texture = data.projectile_texture
	velocity = _direction * data.speed_tiles * GameConstants.PX_PER_TILE
	rotation = velocity.angle() + PI / 2

	# One timer bounds each flight leg; every wall bounce restarts it.
	_leg_timer = Timer.new()
	_leg_timer.one_shot = true
	_leg_timer.timeout.connect(queue_free)
	add_child(_leg_timer)
	_start_leg()

func _start_leg() -> void:
	_leg_timer.start(float(data.range_per_leg_tiles) / data.speed_tiles)

func _physics_process(delta: float) -> void:
	# Only terrain is in the collision mask, so any collision is a wall.
	var collision := move_and_collide(velocity * delta)
	if collision:
		if _bounces_left <= 0:
			queue_free()
			return
		_bounces_left -= 1
		velocity = velocity.bounce(collision.get_normal())
		rotation = velocity.angle() + PI / 2
		_start_leg()

func get_damage() -> int:
	return roundi(data.base_damage + skill * data.skill_scaling)

func reached_hurtbox() -> void:
	queue_free()
