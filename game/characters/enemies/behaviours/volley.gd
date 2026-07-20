extends Behaviour
class_name Volley

# Plants its feet and lobs a burst of shots at the player, then → done_state.
# A parting reaction with no range gate: it keeps firing in the player's direction
# even once they're out of detection.
#
# Two ways to end the burst, and two cadences:
#   shot_count     — stop after N shots landed (the default).
#   duration       — >0 stops after that many seconds instead, however many shots fit.
#   pulse_interval — >0 fires on a fixed metronome; 0 (default) tries every frame, so
#                    the cadence is the spell's own cooldown.
# Duration + interval is a sustained wave (thornmess's spore screen); shot_count +
# cooldown is a regular aimed burst. Same beat, different dials.

@export var caster_path: NodePath
@export var spell: SpellResource
@export var shot_count: int = 3
@export var duration: float = 0.0 ## >0: fire for this long instead of counting shots.
@export var pulse_interval: float = 0.0 ## >0: fixed cadence; 0 uses the spell's cooldown.
@export var attack_anim: String = "attack"
@export var done_state: String = "Idle"

@onready var _caster: SpellCaster = get_node(caster_path)
var _shots_left: int = 0
var _duration_timer: Timer
var _pulse_timer: Timer
var _pulse_ready: bool = true

func _ready() -> void:
	super()
	if duration > 0.0:
		_duration_timer = creature.make_timer(func(): go_to(done_state))
	if pulse_interval > 0.0:
		_pulse_timer = creature.make_timer(func(): _pulse_ready = true)

# Don't let a dispatcher roll this beat while the spell is still cooling — it would
# stand there doing nothing until the cooldown lapsed.
func can_run() -> bool:
	return _caster.ready_for(spell)

func enter() -> void:
	creature.velocity = Vector2.ZERO
	creature.play(attack_anim)
	_shots_left = shot_count
	_pulse_ready = true
	if _duration_timer:
		_duration_timer.start(duration)

func exit() -> void:
	if _duration_timer:
		_duration_timer.stop()
	if _pulse_timer:
		_pulse_timer.stop()

func physics_update(_delta: float) -> void:
	var player := creature.get_target()
	if player:
		creature.face(player.global_position.x - creature.global_position.x)
	elif _requires_target():
		go_to(done_state)
		return
	if not _pulse_ready or not _fire(player):
		return
	if _pulse_timer:
		_pulse_ready = false
		_pulse_timer.start(pulse_interval)
	# On a duration burst the timer ends the state, so shots go uncounted.
	if _duration_timer:
		return
	_shots_left -= 1
	if _shots_left <= 0:
		go_to(done_state)

# Override point: subclasses that need to alter the fired direction (e.g. a
# rotating ring) hook in here instead of duplicating physics_update. `player` is null
# only when _requires_target() is false, i.e. the aim doesn't depend on them.
func _fire(player: Node2D) -> bool:
	return _caster.cast(spell, aim_at(player))

# Aimed bursts abort when their target vanishes; an absolute-aim spray (a ring wave)
# doesn't care and keeps painting the arena.
func _requires_target() -> bool:
	return true
