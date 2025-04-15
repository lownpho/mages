extends Node
class_name State

# Callback definitions
signal on_enter
signal on_exit
signal on_update(delta: float)
signal on_physics_update(delta: float)
signal on_input(event: InputEvent)

func emit_enter() -> void:
	print("Entering state: ", name)
	on_enter.emit()

func emit_exit() -> void:
	print("Exiting state: ", name)
	on_exit.emit()

func emit_update(delta: float) -> void:
	on_update.emit(delta)

func emit_physics_update(delta: float) -> void:
	on_physics_update.emit(delta)

func emit_input(event: InputEvent) -> void:
	on_input.emit(event)
