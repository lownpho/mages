extends Chase
class_name Flee

# Bolts in a RANDOM direction picked on enter (not simply away from the player), so every
# re-entry — including the post-Barrage one — rolls a fresh escape line. RetreatProbe is kept
# pointed along the flee direction; hitting a wall there is what "cornered" means.

@export var retreat_probe_path: NodePath
@export var cornered_state: String = "Barrage"
@export var retreat_range: float = 12.0

@onready var _retreat: RayCast2D = get_node(retreat_probe_path)

var _dir := Vector2.RIGHT

func enter() -> void:
	super()
	_retreat.enabled = true
	_dir = _pick_direction()

func exit() -> void:
	super()
	_retreat.enabled = false

# A handful of rolls, keeping the first that isn't wall-blocked at probe range; a fully
# boxed-in viper keeps the last roll and corners immediately, which is the fight trigger.
func _pick_direction() -> Vector2:
	var dir := Vector2.RIGHT
	for _i in 8:
		dir = Vector2.from_angle(randf() * TAU)
		_retreat.target_position = dir * retreat_range
		_retreat.force_raycast_update()
		if not _retreat.is_colliding():
			return dir
	return dir

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

	_retreat.target_position = _dir * retreat_range
	_retreat.force_raycast_update()
	if _retreat.is_colliding():
		creature.fsm.transition_to(cornered_state)
		return

	creature.velocity = _velocity(to_player, delta)
	creature.move_and_slide()

func _velocity(_to_player: Vector2, _delta: float) -> Vector2:
	return _dir * speed
