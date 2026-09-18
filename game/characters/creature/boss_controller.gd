extends Node
class_name BossController

## Everything a Boss fight knows that a beat does not, in one node: the ordered Rotation, the
## Intensity scalar, the Phase cursor, the Rep count and the Counter latch. Beats keep doing
## exactly what they always did; this is what turns a set of them into a fight that tightens.
## The dispatcher half of the same story is Cycle, which reads this state and writes it back as
## the Rotation moves.
##
## **Intensity (M)** is the design's only escalation axis. It steps up on every Phase advance
## (including across the Rotation wrap) and steps back down on a clean Counter, clamped to
## [1.0, 2.0]. It scales TIMING only — wind-ups, Tails, rep gaps and movement speed — never
## damage, never projectile speed and never density. Every dial it shortens has a hard floor,
## because the player's answer to a Phase is positional or timing: a telegraph that shrinks
## past readability would break the promise the Phase's Counter was authored to keep. A ×2
## Boss is the same fight with less slack, not a different one.
##
## **Counters** are detected here, from signals that already exist: the boss's own hurtbox, its
## `dash_blocked`, the player's hurtbox, and the escort group's membership. No new sensing,
## physics or collision. Exactly one kind per beat, credited at most once per Phase, so a
## Phase can undo at most one step of M.

## Intensity stepped. One sting up, a distinct one back, and every animation sped up — the
## player has to be able to SEE the fight tighten or the brake is invisible.
signal intensity_changed(intensity: float)
## A Phase's Counter was answered. Carries the kind, so feedback can tell a clean Phase from a
## punish.
signal countered(kind: Behaviour.Counter)

## One step of Intensity per Phase advance, and the same step back per clean Counter.
const STEP := 0.12
const MIN_INTENSITY := 1.0
const MAX_INTENSITY := 2.0
## Floors under the dials Intensity tightens. Not dials an author can tune away: the player's
## answer to a Phase is positional or timing, so the tell has a readable length it keeps.
const TELEGRAPH_FLOOR := 0.35
const TAIL_FLOOR := 0.40
const REP_GAP_FLOOR := 0.30
## Ceiling on scaled movement speed. A Boss closes, but never outruns the player outright
## (the player walks at 80 px/s).
const SPEED_CAP := 75.0
## Longest Free beat allowed between Phases.
const FREE_BEAT_CAP := 1.5

## The ordered Rotation: Phase state names, in the order they play. Order is authored, never
## rolled, and the Rotation wraps back to the first entry.
@export var phases: Array[String] = []
## Incoming-damage scale held while the current Phase's escort still stands. An ADDS Phase is
## answered by clearing the adds, and this is what makes clearing them the answer rather than
## an option.
@export var escort_armour: float = 0.25

## The escalation scalar. Global and monotonic for the whole fight; reset only by the
## out-of-combat leash.
var intensity: float = MIN_INTENSITY
## Which Phase in the Rotation is current, and how many of its Reps have played.
var cursor: int = 0
var reps: int = 0
## True while the current Phase's recovery Tail is running — its punish window.
var tail_open: bool = false

var _creature: Creature
## The Phase being fought right now, and whether its Counter has already been credited.
var _phase: Behaviour
var _credited: bool = false
## Damage the player took while this Phase ran (the UNTOUCHED clause).
var _player_hurt: bool = false
var _player_box: Area2D
## True while this node is the one holding the escort armour up, so it never stomps a scale a
## beat authored for itself.
var _armoured: bool = false
## True once the current Phase's escort has actually been seen standing. An ADDS Counter is the
## escort CLEARING, which is not the same as there being none yet: the boss spends its summon
## wind-up with an empty floor, and crediting that would hand the player a rollback for nothing.
var _adds_seen: bool = false

func _ready() -> void:
	# Children are ready before their parent, so the creature's @onready refs aren't assigned
	# yet — reach for the Hurtbox node by name instead of through them.
	_creature = get_parent() as Creature
	if _creature == null:
		push_error("BossController belongs on a Creature")
		return
	var box := _creature.get_node_or_null("Hurtbox") as Area2D
	if box:
		box.hurt.connect(_on_hurt)
	_creature.dash_blocked.connect(_on_blocked)

# --- the Rotation ---------------------------------------------------------------------

## The Phase name the cursor points at, or "" when no Rotation is authored.
func cursor_phase_name() -> String:
	return phases[cursor] if cursor >= 0 and cursor < phases.size() else ""

## Move the cursor to `phase`, rewinding the Rep count and stepping Intensity. Every change of
## Phase goes through here — the wrap included — so M rises once per Phase however the fight
## got to it.
func jump_to(phase: String) -> void:
	var index := phases.find(phase)
	if index >= 0:
		cursor = index
	reps = 0
	intensity = minf(intensity + STEP, MAX_INTENSITY)
	intensity_changed.emit(intensity)

## The whole fight rewound: M back to its opening value, the Rotation back to its first Phase.
func reset() -> void:
	end_phase()
	intensity = MIN_INTENSITY
	cursor = 0
	reps = 0
	_credited = false
	_player_hurt = false
	_adds_seen = false
	intensity_changed.emit(intensity)

# --- the Phase lifecycle (driven by Cycle) ---------------------------------------------

## A Phase is opening: watch the player for the UNTOUCHED clause, and open a fresh Counter
## latch. Called once per visitation, never per Rep — a Rep must not clear the latch, or a
## Phase could undo more than one step of M.
func begin_phase(beat: Behaviour) -> void:
	_phase = beat
	_credited = false
	_player_hurt = false
	_adds_seen = false
	_watch_player(_player_hurtbox())

## The Phase's last Rep is done. UNTOUCHED is settled here rather than at the end of the Tail,
## because the Tail is the player's punish window: taking a hit inside it is not a failure to
## answer, and the feedback from answering belongs the moment the beat is survived.
func finish_phase() -> void:
	if _phase == null or reps <= 0 or _credited:
		return
	if _phase.counter_kind == Behaviour.Counter.UNTOUCHED and not _player_hurt:
		_credit()

## The Phase is over: no Counter can land on it any more, and nothing it borrowed is still
## held (the escort armour, the player's hurt signal).
func end_phase() -> void:
	close_tail()
	_phase = null
	_set_armour(false)
	_watch_player(null)

func open_tail() -> void:
	tail_open = true

func close_tail() -> void:
	tail_open = false

## The Phase being fought right now, or null (between Phases, or during a Free beat).
func live_phase() -> Behaviour:
	return _phase

# --- timing dials ----------------------------------------------------------------------

## Telegraph / wind-up duration at the current Intensity. The player has to be able to read
## this, so it never crosses the floor.
func scale_telegraph(base: float) -> float:
	return maxf(base / intensity, TELEGRAPH_FLOOR)

## The punish window at the current Intensity.
func scale_tail(base: float) -> float:
	return maxf(base / intensity, TAIL_FLOOR)

## The beat between two Reps at the current Intensity.
func scale_gap(base: float) -> float:
	return maxf(base / intensity, REP_GAP_FLOOR)

## Movement speed at the current Intensity — the answer to walking away. Capped, so an
## escalated Boss closes the gap without outrunning the player outright.
func scale_speed(base: float) -> float:
	return minf(base * intensity, SPEED_CAP)

# --- Counter detection -----------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _creature == null or _phase == null:
		return
	# An ADDS Phase's escort is both its armour and its Counter: while the adds stand the boss
	# is armoured (clearing them is the answer, not a chore beside it), and the moment they come
	# down the Counter lands. "Come down" and not "are absent" — the summon wind-up runs with an
	# empty floor, and only an escort that has been seen standing can be cleared.
	if _phase.counter_kind != Behaviour.Counter.ADDS:
		return
	var adds_up := not _phase.group_clear()
	_set_armour(adds_up)
	if adds_up:
		_adds_seen = true
	elif _adds_seen:
		_credit()

func _on_hurt(_damage: int, _source: Node) -> void:
	# Damage landing inside the Tail IS the punish: the beat's telegraph was the question and
	# this is the answer.
	if _phase and _phase.counter_kind == Behaviour.Counter.PUNISH and tail_open:
		_credit()

func _on_blocked() -> void:
	if _phase and _phase.counter_kind == Behaviour.Counter.WALL:
		_credit()

func _on_player_hurt(_damage: int, _source: Node) -> void:
	_player_hurt = true

func _credit() -> void:
	if _credited or _phase == null:
		return
	_credited = true  # the Phase's rollback is spent
	intensity = maxf(intensity - STEP, MIN_INTENSITY)
	intensity_changed.emit(intensity)
	_phase.countered.emit(_phase.counter_kind)
	countered.emit(_phase.counter_kind)

func _set_armour(on: bool) -> void:
	if on == _armoured:
		return
	_armoured = on
	_creature.incoming_damage_scale = escort_armour if on else 1.0

# The player's own hurtbox, so "took no damage this Phase" reads the signal the player already
# emits for its own damage numbers. A target without one (a test dummy, a summon) simply never
# breaks the UNTOUCHED clause.
func _watch_player(box: Area2D) -> void:
	if box == _player_box:
		return
	if _player_box and _player_box.hurt.is_connected(_on_player_hurt):
		_player_box.hurt.disconnect(_on_player_hurt)
	_player_box = box
	if _player_box and not _player_box.hurt.is_connected(_on_player_hurt):
		_player_box.hurt.connect(_on_player_hurt)

# The player's hurtbox as it stands right now, or null when there is nobody to watch.
func _player_hurtbox() -> Area2D:
	var target := _creature.get_target()
	return target.get_node_or_null("Hurtbox") as Area2D if target else null