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

func _find_creature() -> Creature:
	var node: Node = get_parent()
	while node and not (node is Creature):
		node = node.get_parent()
	return node as Creature
