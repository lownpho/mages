extends Behaviour
class_name Chase

@export var chase_probe_path: NodePath
@export var attack_probe_path: NodePath
@export var attack_state: String = "Attack"
@export var lost_state: String = "Idle"
@export var speed: float = 16.0
@export var run_anim: String = "run" ## Played while chasing; override for art with different tag names.

@onready var _chase: RayCast2D = get_node(chase_probe_path)
@onready var _attack: RayCast2D = get_node(attack_probe_path)

func enter() -> void:
	_chase.enabled = true
	_attack.enabled = true
	enemy.play(run_anim)

func exit() -> void:
	_chase.enabled = false
	_attack.enabled = false

func physics_update(delta: float) -> void:
	var player := enemy.get_target()
	if not player:
		enemy.fsm.transition_to(lost_state)
		return

	var to_player := player.global_position - enemy.global_position
	_chase.look_at(player.global_position)
	_attack.look_at(player.global_position)
	enemy.face(to_player.x)

	if enemy.probe_sees(_attack):
		enemy.fsm.transition_to(attack_state)
	elif enemy.probe_sees(_chase):
		enemy.velocity = _velocity(to_player, delta)
		enemy.move_and_slide()
	else:
		enemy.fsm.transition_to(lost_state)

# Movement seam: subclasses (e.g. WeaveChase) override this to change how it closes.
func _velocity(to_player: Vector2, _delta: float) -> Vector2:
	return to_player.normalized() * speed
