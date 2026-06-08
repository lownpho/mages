extends Behaviour
class_name Volley

# Plants its feet and fires a fixed burst of shots at the player, then hands off to
# done_state. A parting-shot reaction: it keeps firing only while detect_probe sees
# the target, bailing to lost_state if they slip away before the burst finishes.
# Keep the weapon's fire_cooldown below shot_interval so no shots are dropped.

@export var detect_probe_path: NodePath
@export var weapon_path: NodePath
@export var weapon_data: WeaponResource
@export var shot_count: int = 3
@export var shot_interval: float = 0.6 ## Cadence between shots; keep above the weapon's fire_cooldown.
@export var attack_anim: String = "attack"
@export var lost_state: String = "Idle" ## Player left detect_probe before the burst finished.
@export var done_state: String = "Idle" ## Burst finished.

@onready var _detect: RayCast2D = get_node(detect_probe_path)
@onready var _weapon: EnemyWeapon = get_node(weapon_path)
var _timer: Timer
var _shots_left: int = 0

func _ready() -> void:
	super()
	if weapon_data:
		_weapon.setup_for_enemy(weapon_data)
	_timer = enemy.make_timer(_fire_next)

func enter() -> void:
	_detect.enabled = true
	enemy.velocity = Vector2.ZERO
	enemy.play(attack_anim)
	_shots_left = shot_count
	_fire_next()

func exit() -> void:
	_detect.enabled = false
	_timer.stop()

func physics_update(_delta: float) -> void:
	if not enemy.look_for_player(_detect):
		enemy.fsm.transition_to(lost_state)
		return
	var player := enemy.get_player()
	enemy.face(player.global_position.x - enemy.global_position.x)

func _fire_next() -> void:
	if _shots_left <= 0:
		enemy.fsm.transition_to(done_state)
		return
	_shots_left -= 1
	var player := enemy.get_player()
	if player:
		enemy.face(player.global_position.x - enemy.global_position.x)
		_weapon.try_fire(enemy.global_position, player.global_position, enemy.skill)
	_timer.start(shot_interval)
