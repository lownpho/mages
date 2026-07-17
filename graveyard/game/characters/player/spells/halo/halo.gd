extends Node2D

## Halo: orbs orbit the caster for the duration, damaging enemies they sweep
## through. The node tracks the caster every frame and spins its orbs around it.
## Each orb is a DamageZone, so a hurtbox takes damage once per pass — it re-enters
## on the next revolution for another hit. No aim; proximity does the work. The
## node frees itself when the duration ends.

const _OrbScene = preload("res://characters/player/spells/halo/halo_orb.tscn")

var data: HaloResource
var skill: int = 0
var caster_defence: int = 0

var _caster: Node2D
var _angle: float = 0.0
var _radius: float = 0.0
var _orbs: Array[Node2D] = []

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	skill = caster.skill
	var dfc = caster.get("defence")
	caster_defence = dfc if dfc != null else 0
	_caster = caster
	global_position = caster.global_position

func _ready() -> void:
	_radius = data.orbit_radius_tiles * GameConstants.PX_PER_TILE
	var damage := data.damage_for(skill, 0, caster_defence)
	for i in data.orb_count:
		var orb = _OrbScene.instantiate()
		orb.damage = damage
		if data.orb_texture:
			orb.get_node("Sprite2D").texture = data.orb_texture
		add_child(orb)
		_orbs.append(orb)
	_position_orbs()

	var life := Timer.new()
	life.one_shot = true
	life.autostart = true
	life.wait_time = data.duration
	life.timeout.connect(queue_free)
	add_child(life)

func _physics_process(delta: float) -> void:
	if is_instance_valid(_caster):
		global_position = _caster.global_position
	if data.orbit_period > 0.0:
		_angle += TAU * delta / data.orbit_period
	_position_orbs()

func _position_orbs() -> void:
	var n := _orbs.size()
	for i in n:
		_orbs[i].position = Vector2(_radius, 0).rotated(_angle + TAU * i / n)
