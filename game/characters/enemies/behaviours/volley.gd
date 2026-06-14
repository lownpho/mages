extends Behaviour
class_name Volley

# Plants its feet and lobs a fixed burst of shots at the player, then → done_state.
# A parting reaction with no range gate: it keeps firing in the player's direction
# even once they're out of detection. Cadence is the weapon's own fire_cooldown —
# each frame it tries to fire and only counts a shot when the weapon lets one go.

@export var weapon_path: NodePath
@export var weapon_data: WeaponResource
@export var shot_count: int = 3
@export var attack_anim: String = "attack"
@export var done_state: String = "Idle"

@onready var _weapon: EnemyWeapon = get_node(weapon_path)
var _shots_left: int = 0

func _ready() -> void:
	super()
	if weapon_data:
		_weapon.setup_for_enemy(weapon_data)

func enter() -> void:
	enemy.velocity = Vector2.ZERO
	enemy.play(attack_anim)
	_shots_left = shot_count

func physics_update(_delta: float) -> void:
	var player := enemy.get_target()
	if not player:
		enemy.fsm.transition_to(done_state)
		return
	enemy.face(player.global_position.x - enemy.global_position.x)
	if _weapon.try_fire(enemy.global_position, player.global_position, enemy.skill):
		_shots_left -= 1
		if _shots_left <= 0:
			enemy.fsm.transition_to(done_state)
