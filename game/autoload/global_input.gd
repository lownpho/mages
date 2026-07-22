extends Node

## Autoloaded. Tracks which device drives the game — mouse+keyboard or gamepad —
## flipping on the last meaningful input, and owns the "UI has captured input"
## flag the HUD raises while the player navigates slots with a controller.
## Consumers read the properties or connect to the signals; nothing here handles
## gameplay actions itself.

signal device_changed(gamepad: bool)
signal ui_capture_changed(captured: bool)

## True while the last input came from a gamepad. Drives aim source (stick vs
## cursor), OS cursor visibility, and where a discarded item lands.
var using_gamepad := false

## True while the HUD owns input for slot navigation — gameplay input (movement,
## casts, page cycling) must stand down. Set only via set_ui_captured.
var ui_captured := false

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_set_gamepad(true)
	elif event is InputEventJoypadMotion:
		# Deadzone: resting sticks/triggers report noise; only a deliberate push flips.
		if absf(event.axis_value) > 0.5:
			_set_gamepad(true)
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_set_gamepad(false)

func _set_gamepad(gamepad: bool) -> void:
	if using_gamepad == gamepad:
		return
	using_gamepad = gamepad
	# On pad the cursor is meaningless (aim comes from the stick) — hide it.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if gamepad else Input.MOUSE_MODE_VISIBLE
	device_changed.emit(gamepad)

func set_ui_captured(captured: bool) -> void:
	if ui_captured == captured:
		return
	ui_captured = captured
	ui_capture_changed.emit(captured)
