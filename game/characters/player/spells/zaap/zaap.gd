extends CharacterBody2D

## Zaap bolt: flies toward the cursor; the first enemy it zaps starts the
## chain — after each hit it leaps to the nearest enemy (any enemy but the one
## it's currently leaving, so it can double back onto an earlier target),
## until it runs out of bounces or targets. Damage lands through the enemies'
## Hurtbox exactly like a bullet (it's in the "bullets" group), but
## reached_hurtbox() bounces instead of despawning. Dies on walls.

var data: ZaapResource
var skill: int = 0
var speed: int = 0

var _direction: Vector2 = Vector2.RIGHT
var _target: Node2D = null
var _last_victim: Node2D = null
var _hits_left: int = 0
var _leg_timer: Timer

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	skill = caster.skill
	var spd = caster.get("speed")
	speed = spd if spd != null else 0
	global_position = caster.global_position
	_direction = (caster.get_global_mouse_position() - caster.global_position).normalized()

func _speed() -> float:
	return data.speed_tiles * GameConstants.PX_PER_TILE

func _ready() -> void:
	_hits_left = 1 + data.bounces
	if data.projectile_texture:
		$Sprite2D.texture = data.projectile_texture
	velocity = _direction * _speed()
	rotation = velocity.angle() + PI / 2

	# One timer bounds each flight leg: the initial range, then every leap.
	# It also cleans up the rare bolt left steering at a target it can't
	# re-trigger (e.g. it never left that enemy's hurtbox).
	_leg_timer = Timer.new()
	_leg_timer.one_shot = true
	_leg_timer.autostart = true
	_leg_timer.wait_time = float(data.range_tiles) / data.speed_tiles
	_leg_timer.timeout.connect(queue_free)
	add_child(_leg_timer)

func _physics_process(delta: float) -> void:
	if _target:
		if not is_instance_valid(_target):
			_retarget_from(global_position)  # target died mid-leap
			if not is_instance_valid(self) or _target == null:
				return
		velocity = global_position.direction_to(_target.global_position) * _speed()
		rotation = velocity.angle() + PI / 2
	if move_and_collide(velocity * delta):
		queue_free()  # wall

func get_damage() -> int:
	return data.damage_for(skill, speed)

# Called by the Hurtbox we just zapped (bullets-group contract). The hurt was
# already applied; here we only decide where the chain goes next.
func reached_hurtbox() -> void:
	_hits_left -= 1
	# The victim is whichever enemy we're overlapping right now.
	var victim := _nearest_enemy(null, global_position, 3.0 * GameConstants.PX_PER_TILE)
	if victim:
		_last_victim = victim
	if _hits_left <= 0:
		queue_free()
		return
	_retarget_from(victim.global_position if victim else global_position)

func _retarget_from(from: Vector2) -> void:
	# Exclude only the enemy just zapped, so the chain can't instantly
	# re-trigger its own hurtbox — but it's free to loop back later.
	var next := _nearest_enemy(_last_victim, from, data.bounce_range_tiles * GameConstants.PX_PER_TILE)
	if next == null:
		_target = null
		queue_free()
		return
	_target = next
	# Fresh leg bound, with slack for the target moving away.
	_leg_timer.start(2.0 * data.bounce_range_tiles / data.speed_tiles)

func _nearest_enemy(exclude: Node2D, from: Vector2, max_range_px: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_range_px * max_range_px
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == exclude or enemy.is_queued_for_deletion():
			continue
		var d: float = from.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best
