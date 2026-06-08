extends Behaviour
class_name FireWhenInRange

@export var weapon_path: NodePath
@export var weapon_data: WeaponResource
@export var attack_probe_path: NodePath
@export var out_of_range_state: String = "Chase"
@export var attack_anim: String = "idle" ## Played while firing; defaults to the idle pose.

@onready var _weapon: EnemyWeapon = get_node(weapon_path)
@onready var _probe: RayCast2D = get_node(attack_probe_path)

func _ready() -> void:
	super()
	if weapon_data:
		_weapon.setup_for_enemy(weapon_data)

func enter() -> void:
	_probe.enabled = true
	enemy.play(attack_anim)

func exit() -> void:
	_probe.enabled = false

func physics_update(_delta: float) -> void:
	var player := enemy.get_player()
	if not player:
		enemy.fsm.transition_to(out_of_range_state)
		return

	_probe.look_at(player.global_position)
	enemy.face(player.global_position.x - enemy.global_position.x)

	if enemy.probe_sees(_probe):
		_weapon.try_fire(enemy.global_position, player.global_position, enemy.skill)
	else:
		enemy.fsm.transition_to(out_of_range_state)
