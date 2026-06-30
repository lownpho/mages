extends Behaviour
class_name ChargeDash

# The committed lunge. Locks a heading at the target the moment it launches, then drives
# straight at dash_speed for dash_distance, shedding a pair of flank bullets every
# drop_interval of travel. It never steers — hitting terrain (or anything solid) ends the
# charge early into the recovery window. That "can't corner" straightness is the design:
# trees and pillars are the player's escape.

@export var weapon_path: NodePath
@export var weapon_data: WeaponResource
@export var recover_state: String = "Recover"
@export var dash_speed: float = 72.0 ## px/s (9 tiles/s).
@export var dash_distance: float = 48.0 ## px travelled before recovery (6 tiles).
@export var drop_interval: float = 4.0 ## px between flank-bullet drops (half a tile).
@export var dash_anim: String = "dash"

@onready var _weapon: CreatureWeapon = get_node(weapon_path)

var _dir: Vector2 = Vector2.RIGHT
var _start: Vector2
var _next_drop: float

func _ready() -> void:
	super()
	if weapon_data:
		_weapon.setup_for_creature(weapon_data)

func enter() -> void:
	var target := creature.get_target()
	if target:
		_dir = (target.global_position - creature.global_position).normalized()
	else:
		# No target (committed after losing sight): charge the way we're facing.
		_dir = Vector2.LEFT if creature.sprite.flip_h else Vector2.RIGHT
	creature.face(_dir.x)
	creature.velocity = _dir * dash_speed
	_start = creature.global_position
	_next_drop = drop_interval
	creature.play(dash_anim)

func physics_update(_delta: float) -> void:
	creature.velocity = _dir * dash_speed
	creature.move_and_slide()

	var travelled := _start.distance_to(creature.global_position)
	while travelled >= _next_drop:
		# base direction = dash heading; FlankPattern peels a bullet off each side.
		_weapon.try_fire(creature.global_position, creature.global_position + _dir)
		_next_drop += drop_interval

	if travelled >= dash_distance or creature.is_on_wall():
		creature.fsm.transition_to(recover_state)
