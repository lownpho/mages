extends Cast
class_name Charge

# A Cast whose spell drives the caster: ChargeDash aims once, calls start_dash on whoever
# cast it, and sheds its FlankPattern along the way. Everything a charge needs is already
# Cast's — the wind-up IS the spell's cast_time (the telegraph the player reads), the burst
# IS the spell's shot loop, and the recovery is a Hold pointed back here.
#
# Only two things are true of a moving beat that aren't true of a planted one, and they are
# the whole of this file: the heading stops tracking once the dash is actually under way
# (a charge that kept turning to face you would be a chase, not a charge), and the beat can
# end early against a wall.

## Where a head-on wall slam lands. Empty rides the dash out and hands off to done_state
## as usual — the thornback simply stops; the razorback stuns.
@export var blocked_state: String = ""

func enter() -> void:
	super()
	if not creature.dash_blocked.is_connected(_on_blocked):
		creature.dash_blocked.connect(_on_blocked)

func exit() -> void:
	if creature.dash_blocked.is_connected(_on_blocked):
		creature.dash_blocked.disconnect(_on_blocked)
	super()

# The beat is over when the charge is, not merely when the shots are: a dash tuned to outlast
# its own burst would otherwise hand off to the recovery Hold with the creature still sliding,
# and the punish window would open while it was still moving.
func physics_update(delta: float) -> void:
	if creature.is_dashing():
		_track_aim(creature.get_target())
		return
	super(delta)

# Aim tracks the target right up to launch — the charger lines you up during its wind-up —
# and then the heading is locked, because start_dash has already committed to it and the
# flank bullets peel off that same line. Without this the burst would keep re-sampling the
# caster's aim and the "bullets shed off both flanks" would swivel to follow the player.
func _track_aim(player: Node2D) -> void:
	if not creature.is_dashing():
		super(player)
		return
	if player:
		creature.face(player.global_position.x - creature.global_position.x)

func _on_blocked() -> void:
	if blocked_state != "":
		go_to(blocked_state)
