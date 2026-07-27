extends State
class_name Behaviour

# Extends State so the FSM needs no changes: wires the State signals to
# override-able methods and exposes the owning creature as `creature`.

@onready var creature: Creature = _find_creature()

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

@export_group("Armour")
## Incoming damage while this beat runs; <1 armours (a guard windup), 0 makes the creature
## untouchable outright (the mole underground). Restored on exit so it can't leak past the
## beat. Lives on the base because armour is a property of the beat, not of one shape of
## beat — a rooted guard, an armoured pursuit and a submerged approach all want it.
@export var damage_scale: float = 1.0

var _spent: bool = false

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
	if once and _spent:
		return false
	var frac := 1.0
	if creature.max_health > 0:
		frac = float(creature.health) / float(creature.max_health)
	if frac < health_min or frac > health_max:
		return false
	if not _group_clear():
		return false
	return _ready_to_run()

func _group_clear() -> bool:
	if clear_group == &"":
		return true
	var radius := clear_radius_tiles * GameConstants.PX_PER_TILE
	for node in get_tree().get_nodes_in_group(clear_group):
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
