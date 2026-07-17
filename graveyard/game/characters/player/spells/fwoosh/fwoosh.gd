extends Node2D

## Fwoosh: a wall of fire along the line from the caster toward the cursor,
## captured at cast. It re-damages any enemy overlapping it every tick_interval
## for `duration` by spawning a short-lived rectangular DamageZone each tick (a
## fresh zone re-fires the hurtbox overlap, giving the "pay HP to cross" pulse).
## Damage layer comes from the caster, so it is faction-agnostic.
##
## It also drops a StaticBody2D on the Spell Barrier layer for its lifetime: enemy
## bullets mask that layer (see BaseBullet) and die on the wall, while the player's
## bullets and enemy bodies don't mask it and pass straight through — the wall is
## one-way by construction.

const DamageZoneScript = preload("res://components/damage_zone.gd")

var data: FwooshResource
var _caster: Node2D
var skill: int = 0
var caster_speed: int = 0
var _layer: int = 0
var _center: Vector2 = Vector2.ZERO
var _angle: float = 0.0
var _ticks_total: int = 0
var _ticks_fired: int = 0

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	_caster = caster
	skill = caster.skill
	var spd = caster.get("speed")
	caster_speed = spd if spd != null else 0
	var dir: Vector2 = caster.get_aim_direction()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	_angle = dir.angle()
	var length := data.wall_length_tiles * GameConstants.PX_PER_TILE
	_center = caster.global_position + dir * (length * 0.5)

func _ready() -> void:
	var layer_override = _caster.get("bullet_collision_layer")
	_layer = layer_override if layer_override != null else GameConstants.LAYER_PLAYER_BULLETS

	_spawn_barrier()  # physical wall that stops enemy bullets for the whole duration

	_ticks_total = maxi(1, int(round(data.duration / data.tick_interval)))
	_spawn_tick()  # first pulse immediately
	_ticks_fired = 1
	var timer := Timer.new()
	timer.one_shot = false
	timer.wait_time = data.tick_interval
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(_on_tick)

func _on_tick() -> void:
	_spawn_tick()
	_ticks_fired += 1
	if _ticks_fired >= _ticks_total:
		queue_free()

# A StaticBody2D on the Spell Barrier layer, held for the effect's lifetime (it's
# our child, so it frees with us at the last tick). Enemy bullets mask this layer
# and die on it; player bullets and creature bodies don't, so they pass through.
func _spawn_barrier() -> void:
	var length := data.wall_length_tiles * GameConstants.PX_PER_TILE
	var thickness := data.wall_thickness_tiles * GameConstants.PX_PER_TILE
	var barrier := StaticBody2D.new()
	barrier.collision_layer = GameConstants.LAYER_SPELL_BARRIER
	barrier.collision_mask = 0
	barrier.global_position = _center
	barrier.rotation = _angle
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(length, thickness)
	shape.shape = rect
	barrier.add_child(shape)
	add_child(barrier)

func _spawn_tick() -> void:
	var length := data.wall_length_tiles * GameConstants.PX_PER_TILE
	var thickness := data.wall_thickness_tiles * GameConstants.PX_PER_TILE
	var zone := DamageZoneScript.new()
	zone.damage = data.damage_for(skill, caster_speed)
	zone.collision_layer = _layer
	zone.collision_mask = 0
	zone.monitoring = false
	zone.global_position = _center
	zone.rotation = _angle
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(length, thickness)
	shape.shape = rect
	zone.add_child(shape)
	var life := Timer.new()
	life.one_shot = true
	life.autostart = true
	life.wait_time = 0.12
	life.timeout.connect(zone.queue_free)
	zone.add_child(life)
	get_tree().root.add_child.call_deferred(zone)
