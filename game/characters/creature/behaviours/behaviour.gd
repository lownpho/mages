extends State
class_name Behaviour

# Extends State so the FSM needs no changes: wires the State signals to
# override-able methods and exposes the owning creature as `creature`.

@onready var creature: Creature = _find_creature()

## What the player has to DO to answer this beat. Declared on the beat, one kind each; every
## kind reads an event that already exists (see BossController), so a Counter adds no sensing.
## NONE is a beat with nothing to answer — dead time on a boss, which is why the static check
## in test_enemy_scenes fails a Rotation Phase that declares none.
enum Counter { NONE, PUNISH, WALL, ADDS, UNTOUCHED }

## A Counter the player answered landed. Emitted by whoever detects it (BossController) on
## the beat it was declared on, so feedback can hang off the beat rather than off the boss.
signal countered(kind: Counter)

@export_group("Phase")
## The Counter this beat is answered with. See Counter above.
@export var counter_kind: Counter = Counter.NONE
## Playthroughs of the beat before the Phase's Tail opens. Reps are IDENTICAL by design —
## they exist so a beat can be read, not so it can escalate; Intensity is the only dial that
## does that.
@export_range(1, 8) var reps: int = 2
## Recovery after the last Rep: the Phase's punish window. Scaled by Intensity, floored.
@export var tail: float = 1.0
## Beat between two Reps of the same Phase. Scaled by Intensity, floored.
@export var rep_gap: float = 0.6

@export_group("Pattern")
## Relative odds of PatternPicker rolling this beat. 0 keeps it out of the pool entirely,
## so the ordinary states sharing the FSM (Idle, Chase) are never rolled.
@export var pattern_weight: float = 0.0
## Health window (fraction of max) this beat lives in. The pair replaces a single global
## phase threshold: authoring Bloom at 0.25..1 and Spores at 0..0.25 swaps one move out for
## the other at a quarter health, and any number of windows can overlap or chain.
@export_range(0.0, 1.0) var health_min: float = 0.0
@export_range(0.0, 1.0) var health_max: float = 1.0
## Jumps the queue: while a positive-priority beat is eligible the dispatcher takes it
## instead of rolling. Paired with `once` that's a desperation opener — it fires the
## instant its window opens, then never again.
@export var priority: int = 0
## Runs at most once per fight.
@export var once: bool = false

@export_group("Escort")
## While any member of this group stands within `clear_radius_tiles`, the beat refuses to
## run — the seam a boss holds itself back with until its adds are dead. Membership is the
## Pack component's group, so a pack already answers it; the count is positional rather
## than global because streaming keeps other rooms' packs loaded and a grimling three rooms
## away must not pin the fight.
@export var clear_group: StringName = &""
@export var clear_radius_tiles: float = 14.0

@export_group("Range")
## Probe the target must be inside for this beat to be eligible. Range is a question the
## DISPATCHER has to answer before it commits: Cast.attack_probe_path only bails once the
## beat is already running, which reads as a boss rearing into a slam at nothing and then
## thinking better of it. Empty = fires from anywhere.
@export var range_probe_path: NodePath

@export_group("Armour")
## Incoming damage while this beat runs; <1 armours (a guard windup), 0 makes the creature
## untouchable outright (the mole underground). Restored on exit so it can't leak past the
## beat. Lives on the base because armour is a property of the beat, not of one shape of
## beat — a rooted guard, an armoured pursuit and a submerged approach all want it.
@export var damage_scale: float = 1.0

@export_group("Spores")
## Only eligible while the caster stands in its OWN side's spores. The Mycelium's empowerment is a
## whole second beat behind this flag — first rung of a Gate whose fallback is the plain one —
## so no creature carries a "powered" mode, it simply has one more beat than it can always
## reach. Never set it on the beat that LAYS clouds: nothing gets paid for the floor it made
## itself, which is what stops a room of printers spiralling.
@export var needs_cloud: bool = false
## The other half of that pair: refuse while the caster DOES stand in its own spores. Without
## it the ladder drops to the plain beat the moment the empowered one is merely cooling — two
## spells are two cooldown clocks, so a fed creature would spend the gaps firing the weak
## version it was supposed to have traded away. Set on the plain rung, never on the fed one.
@export var refuses_cloud: bool = false

var _spent: bool = false
var _range_probe: RayCast2D

func _ready() -> void:
	on_enter.connect(enter)
	on_enter.connect(func() -> void: _spent = true)
	on_enter.connect(_apply_armour)
	on_exit.connect(exit)
	on_exit.connect(_clear_armour)
	on_physics_update.connect(physics_update)

func _apply_armour() -> void:
	if damage_scale != 1.0:
		creature.incoming_damage_scale = damage_scale

func _clear_armour() -> void:
	if damage_scale != 1.0:
		creature.incoming_damage_scale = 1.0

# Override points for subclasses.
func enter() -> void: pass
func exit() -> void: pass
func physics_update(_delta: float) -> void: pass

## The one eligibility predicate, asked by both the pattern dispatcher and any Hold whose
## next_state points here — so "the spell is still cooling" parks a recovering enemy and
## drops the beat from a boss's roll through the same seam. Subclasses add their own clause
## in `_ready_to_run` rather than overriding this.
func can_run() -> bool:
	if not window_open():
		return false
	if not group_clear():
		return false
	if not _in_range():
		return false
	if needs_cloud and not SporeCloud.feeds(creature):
		return false
	if refuses_cloud and SporeCloud.feeds(creature):
		return false
	return _ready_to_run()

## Whether the beat's own RANGE gate is satisfied. Range is the one gate a Rotation cannot
## wait out: a cooling spell lapses on its own and an escort dies on its own, but a target
## standing out of reach comes back only when the boss goes and gets them. Asked separately
## from `can_run` for that reason — a dispatcher waiting on a cooldown should wait, and one
## waiting on range should close the gap (see Cycle._play).
func range_open() -> bool:
	return _in_range()

func _in_range() -> bool:
	if range_probe_path == NodePath():
		return true
	if _range_probe == null:
		_range_probe = get_node_or_null(range_probe_path) as RayCast2D
	# force_raycast_update inside look_for_target answers regardless of `enabled`, so the
	# probe needs no owner state — it's a ruler, not a sensor another beat is holding.
	return _range_probe != null and creature.look_for_target(_range_probe)

## The beat's own window — is this still the fight's business at all? `once` is spent for
## good and a health window the fight has left does not reopen, so a dispatcher must move on
## rather than wait out a gate that will never open. Everything else a beat can be shut by (a
## cooling spell, an escort still standing, a range probe) is temporary and worth the wait.
func window_open() -> bool:
	if once and _spent:
		return false
	var frac := 1.0
	if creature.max_health > 0:
		frac = float(creature.health) / float(creature.max_health)
	return frac >= health_min and frac <= health_max

## True when nothing of this beat's escort group is left. Public because the BossController asks
## the same question to credit an ADDS Counter and to hold the escort's armour — membership is
## the seam, whether it is read by a beat or by its boss.
##
## `clear_radius_tiles` of 0 means the GROUP IS THE ESCORT and every member counts wherever it
## stands. That is what a boss's own summons author: the radius the default exists for is a
## world-pack concern (streaming keeps a neighbouring room's pack loaded, so a straggler three
## rooms away must not pin a fight), and an escort the boss itself called is not that — a live
## add that has been led out of range is not a dead one.
func group_clear() -> bool:
	if clear_group == &"":
		return true
	# Detached (a run ended mid hand-off): nothing is standing as far as the fight goes.
	if not is_inside_tree():
		return true
	var members := get_tree().get_nodes_in_group(clear_group)
	if clear_radius_tiles <= 0.0:
		return members.is_empty()
	var radius := clear_radius_tiles * GameConstants.PX_PER_TILE
	for node in members:
		# The group is authored on the Pack component, which hangs off the creature and has
		# no position of its own.
		var body := node as Node2D
		if body == null:
			body = node.get_parent() as Node2D
		if body and body.global_position.distance_squared_to(creature.global_position) <= radius * radius:
			return false
	return true

# Subclass seam for can_run (Cast: is the spell off cooldown).
func _ready_to_run() -> bool:
	return true

## The Boss this beat is a Phase of, when it is one. Null for every ordinary enemy — which
## is what keeps the Intensity dials out of the rest of the roster.
func boss() -> BossController:
	return creature.get_node_or_null("BossController") as BossController

func go_to(state: String) -> void:
	creature.fsm.transition_to(state)

# The prologue almost every combat state shares: grab the target, and bail to a
# fallback state if there isn't one. Returns null when it transitioned, so callers
# `if not target: return` right after.
func target_or_go(state: String) -> Node2D:
	var target := creature.get_target()
	if not target:
		go_to(state)
	return target

func aim_at(target: Node2D) -> Vector2:
	return (target.global_position - creature.global_position).normalized()

func _find_creature() -> Creature:
	var node: Node = get_parent()
	while node and not (node is Creature):
		node = node.get_parent()
	return node as Creature
