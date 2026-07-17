extends Behaviour
class_name Reposition

# Flies to a fresh perch when its current one loses the target. A perch sniper enters
# here whenever Snipe can no longer fire — lane blocked, target drifted out of band, or
# gone. A short settle first absorbs momentary line-of-sight breaks (the "more than N
# seconds" grace): it holds and keeps watching, and if the lane clears again it snipes
# from where it stands. Only once the grace lapses does it actually fly, moving to restore
# the firing band — toward the target when too far or blocked, away when too close — until
# it can both see and range the target again. Flying too long without re-perching gives up.
# Reusable by every reposition-on-cover sniper (Owl, Burrower).

@export var detect_probe_path: NodePath   ## longest probe: line of sight to the target
@export var band_probe_path: NodePath     ## firing-band upper edge
@export var close_probe_path: NodePath    ## firing-band lower edge (too close to fire)
@export var speed: float = 48.0           ## reposition flight speed (px/s)
@export var settle_time: float = 1.5      ## hold & re-check before flying (LOS-break grace)
@export var give_up_time: float = 3.0     ## flying this long without re-perching -> lost
@export var regain_state: String = "Snipe"
@export var lost_state: String = "Idle"

@onready var _detect: RayCast2D = get_node(detect_probe_path)
@onready var _band: RayCast2D = get_node(band_probe_path)
@onready var _close: RayCast2D = get_node(close_probe_path)
var _settle: Timer
var _give_up: Timer
var _flying := false

func _ready() -> void:
	super()
	_settle = creature.make_timer(_on_settled)
	_give_up = creature.make_timer(func(): creature.fsm.transition_to(lost_state))

func enter() -> void:
	_detect.enabled = true
	_band.enabled = true
	_close.enabled = true
	_flying = false
	creature.velocity = Vector2.ZERO
	creature.play("idle")
	_settle.start(settle_time)

func exit() -> void:
	_detect.enabled = false
	_band.enabled = false
	_close.enabled = false
	_settle.stop()
	_give_up.stop()

# Grace lapsed without re-perching: commit to flying and arm the give-up timer.
func _on_settled() -> void:
	_flying = true
	creature.play("run")
	_give_up.start(give_up_time)

func physics_update(_delta: float) -> void:
	var player := creature.get_target()
	if not player:
		creature.fsm.transition_to(lost_state)
		return

	var to_player := player.global_position - creature.global_position
	_detect.look_at(player.global_position)
	_band.look_at(player.global_position)
	_close.look_at(player.global_position)
	creature.face(to_player.x)

	# Back inside the firing band with a clear lane -> perch and snipe again.
	if creature.probe_sees(_band) and not creature.probe_sees(_close):
		creature.fsm.transition_to(regain_state)
		return

	if not _flying:
		return  # settling: hold the perch and let the grace timer decide when to fly

	# Restore the band: back off when too close, otherwise close toward a clear lane.
	var dir := to_player.normalized()
	if creature.probe_sees(_close):
		dir = -dir
	creature.velocity = dir * speed
	creature.move_and_slide()
