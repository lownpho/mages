extends State
class_name Behaviour

# Extends State so the FSM needs no changes: wires the State signals to
# override-able methods and exposes the owning enemy as `enemy`.

@onready var enemy: Enemy = _find_enemy()

func _ready() -> void:
	on_enter.connect(enter)
	on_exit.connect(exit)
	on_physics_update.connect(physics_update)

# Override points for subclasses.
func enter() -> void: pass
func exit() -> void: pass
func physics_update(_delta: float) -> void: pass

func _find_enemy() -> Enemy:
	var node: Node = get_parent()
	while node and not (node is Enemy):
		node = node.get_parent()
	return node as Enemy
