extends Behaviour
class_name Flee

# Bolts in a RANDOM direction picked on enter (not simply away from the player), so every
# re-entry — including the post-Barrage one — rolls a fresh escape line. RetreatProbe is kept
# pointed along the flee direction; hitting a wall there is what "cornered" means.
#
# Deliberately NOT a Chase subclass: it shares the run-toward/run-away silhouette but none of
# the logic (no attack probe, no attack hand-off), so inheriting only left dead exports to
# mis-wire.

@export var chase_probe_path: NodePath ## LOS to the target; losing it ends the flight.
@export var retreat_probe_path: NodePath
@export var lost_state: String = "Idle"
@export var cornered_state: String = "Barrage"
@export var speed: float = 32.0
@export var retreat_range: float = 12.0
@export var run_anim: String = "run"

@onready var _chase: RayCast2D = get_node(chase_probe_path)
@onready var _retreat: RayCast2D = get_node(retreat_probe_path)

var _dir := Vector2.RIGHT

func enter() -> void:
	_chase.enabled = true
	_retreat.enabled = true
	creature.play(run_anim)
	_dir = _pick_direction()

func exit() -> void:
	_chase.enabled = false
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

func physics_update(_delta: float) -> void:
	var player := target_or_go(lost_state)
	if not player:
		return

	creature.face(player.global_position.x - creature.global_position.x)

	_chase.look_at(player.global_position)
	if not creature.probe_sees(_chase):
		go_to(lost_state)
		return

	_retreat.target_position = _dir * retreat_range
	_retreat.force_raycast_update()
	if _retreat.is_colliding():
		go_to(cornered_state)
		return

	creature.velocity = _dir * speed
	creature.move_and_slide()
