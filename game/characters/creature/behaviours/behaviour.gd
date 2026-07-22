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

var _spent: bool = false

func _ready() -> void:
	on_enter.connect(enter)
	on_enter.connect(func() -> void: _spent = true)
	on_exit.connect(exit)
	on_physics_update.connect(physics_update)

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
	return _ready_to_run()

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
