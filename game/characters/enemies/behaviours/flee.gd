extends Chase
class_name Flee

# Chase in reverse: closes the gap becomes opening it (_velocity inverted), and the
# "reached the target" handoff becomes "backed into a wall" instead. RetreatProbe is kept
# pointed opposite the player each frame (mirroring how Chase aims _chase/_attack at them)
# and going wall-first there is what "cornered" means, since there's no fixed retreat
# direction to probe up front.

@export var retreat_probe_path: NodePath
@export var cornered_state: String = "Barrage"
@export var retreat_range: float = 12.0

@onready var _retreat: RayCast2D = get_node(retreat_probe_path)

func enter() -> void:
	super()
	_retreat.enabled = true

func exit() -> void:
	super()
	_retreat.enabled = false

func physics_update(delta: float) -> void:
	var player := creature.get_target()
	if not player:
		creature.fsm.transition_to(lost_state)
		return

	var to_player := player.global_position - creature.global_position
	creature.face(to_player.x)

	_chase.look_at(player.global_position)
	if not creature.probe_sees(_chase):
		creature.fsm.transition_to(lost_state)
		return

	var away := -to_player.normalized()
	_retreat.target_position = away * retreat_range
	_retreat.force_raycast_update()
	if _retreat.is_colliding():
		creature.fsm.transition_to(cornered_state)
		return

	creature.velocity = _velocity(to_player, delta)
	creature.move_and_slide()

func _velocity(to_player: Vector2, _delta: float) -> Vector2:
	return -to_player.normalized() * speed
