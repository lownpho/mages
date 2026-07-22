extends Behaviour
class_name Hold

# The timed beat every creature shares: plant, play a pose, and hand off once the clock
# lapses AND the destination is willing to run. Idling, the burn window between a boss's
# patterns, an armoured guard, and the recovery between two shots are all this shape with
# different dials — detection on or off, armour under 1.0, a wait that ends on a spell's
# cooldown rather than the timer.

@export var anim: String = "idle"
@export var min_time: float = 1.5
@export var max_time: float = 4.0
@export var next_state: String = "Idle"

@export_group("Detection")
## Optional LOS probe. Both destinations below read it; leave the path empty for a beat
## that shouldn't look around at all (a boss's rest — the fight is already committed).
@export var probe_path: NodePath
## Target came into view. The idle→engage edge.
@export var seen_state: String = ""
## Target left view. The recover→chase edge: an enemy waiting out its cooldown gives up
## and re-closes the moment the player walks off, instead of standing still until the
## spell comes back and only then noticing.
@export var lost_state: String = ""
## Taking a hit counts as spotting the attacker — for rooted defenders that should snap
## into their guard even when the blow lands from outside the probe's cone.
@export var alert_on_hit: bool = false

@export_group("Armour")
## Incoming damage while held; <1 armours. Restored on exit so it can't leak past the beat.
@export var damage_scale: float = 1.0

var _timer: Timer
var _elapsed: bool = false
var _probe: RayCast2D

func _ready() -> void:
	super()
	_timer = creature.make_timer(func() -> void: _elapsed = true)
	if probe_path != NodePath():
		_probe = get_node(probe_path)

func enter() -> void:
	creature.velocity = Vector2.ZERO
	creature.play(anim)
	if damage_scale != 1.0:
		creature.incoming_damage_scale = damage_scale
	if _probe:
		_probe.enabled = true
	if alert_on_hit and not creature.hurtbox.hurt.is_connected(_on_hit):
		creature.hurtbox.hurt.connect(_on_hit)
	# Timer.start(0) keeps the previous wait_time instead of expiring at once, so a
	# zero-length hold (a pure wait-for-cooldown) skips the timer entirely.
	var wait := randf_range(min_time, max_time)
	_elapsed = wait <= 0.0
	if not _elapsed:
		_timer.start(wait)

func exit() -> void:
	_timer.stop()
	if damage_scale != 1.0:
		creature.incoming_damage_scale = 1.0
	if _probe:
		_probe.enabled = false
	if creature.hurtbox.hurt.is_connected(_on_hit):
		creature.hurtbox.hurt.disconnect(_on_hit)

func physics_update(delta: float) -> void:
	if _probe and (seen_state != "" or lost_state != ""):
		var seen := creature.look_for_target(_probe)
		if seen and seen_state != "":
			go_to(seen_state)
			return
		if not seen and lost_state != "":
			go_to(lost_state)
			return
	_tick(delta)
	if _elapsed and _next_ready():
		go_to(next_state)

# Movement seam: Wander overrides this to drift while it holds.
func _tick(_delta: float) -> void:
	pass

# The hand-off waits on the destination's own eligibility, so a Recover beat pointed at a
# Cast simply sits there until that spell is off cooldown — the wait between two shots is
# an FSM state like any other, not a counter hidden inside the attack.
func _next_ready() -> bool:
	var state: State = creature.fsm.states.get(next_state)
	return not (state is Behaviour) or state.can_run()

func _on_hit(_damage: int, _source: Node) -> void:
	if seen_state != "":
		go_to(seen_state)
