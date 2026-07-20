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
	creature.play(run_anim)

func exit() -> void:
	_chase.enabled = false
	_attack.enabled = false

func physics_update(delta: float) -> void:
	var player := target_or_go(lost_state)
	if not player:
		return

	var to_player := player.global_position - creature.global_position
	_chase.look_at(player.global_position)
	_attack.look_at(player.global_position)
	creature.face(to_player.x)

	if creature.probe_sees(_attack):
		go_to(attack_state)
	elif creature.probe_sees(_chase):
		creature.velocity = _velocity(to_player, delta)
		creature.move_and_slide()
	else:
		go_to(lost_state)

# Movement seam: subclasses (e.g. WeaveChase) override this to change how it closes.
func _velocity(to_player: Vector2, _delta: float) -> Vector2:
	return to_player.normalized() * speed
