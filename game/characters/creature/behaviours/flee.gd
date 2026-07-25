extends Behaviour
class_name Flee

# Bolts in a RANDOM direction picked on enter (not simply away from the player), so every
# re-entry — including the post-Barrage one — rolls a fresh escape line. RetreatProbe is kept
# pointed along the flee direction; hitting a wall there is what "cornered" means.
#
# Two shapes come out of the same node, depending on whether `duration` is set. Unset, the
# flight only ends when the creature is cornered or loses the target — the viper, running
# until the room stops it. Set, the retreat is on a clock and lands in `done_state`, which
# is the hit-and-run loop: poke, bolt for a beat, close again (the moth). The clock is
# deliberately the same seam Approach uses for its pursuit, so both halves of a
# closer/retreater read alike.
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

@export_group("Clock")
## Seconds before the retreat gives up and hands off. 0 = flee until cornered or lost.
@export var duration: float = 0.0
## Where the clock lands. Falls back to lost_state when empty.
@export var done_state: String = ""

@onready var _chase: RayCast2D = get_node(chase_probe_path)
@onready var _retreat: RayCast2D = get_node(retreat_probe_path)

var _dir := Vector2.RIGHT
var _timer: Timer

func _ready() -> void:
	super()
	if duration > 0.0:
		_timer = creature.make_timer(func() -> void: go_to(_done()))

func enter() -> void:
	_chase.enabled = true
	_retreat.enabled = true
	creature.play(run_anim)
	_dir = _pick_direction()
	if _timer:
		_timer.start(duration)

func exit() -> void:
	_chase.enabled = false
	_retreat.enabled = false
	if _timer:
		_timer.stop()

# Running out of clock is a successful disengage, not a failed one, so it gets its own
# destination — a beat only needs to name it when it differs from losing the target.
func _done() -> String:
	return done_state if done_state != "" else lost_state

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
