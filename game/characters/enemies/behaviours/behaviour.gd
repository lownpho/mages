extends State
class_name Behaviour

# Extends State so the FSM needs no changes: wires the State signals to
# override-able methods and exposes the owning creature as `creature`.

@onready var creature: Creature = _find_creature()

func _ready() -> void:
	on_enter.connect(enter)
	on_exit.connect(exit)
	on_physics_update.connect(physics_update)

# Override points for subclasses.
func enter() -> void: pass
func exit() -> void: pass
func physics_update(_delta: float) -> void: pass

## Veto seam for the pattern dispatcher: a state that can't do anything useful right now
## (a Volley whose spell is still cooling) reports false and PatternPicker rolls something
## else, instead of committing the boss to a beat that would stand there doing nothing.
func can_run() -> bool:
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
