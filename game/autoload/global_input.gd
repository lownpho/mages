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

## True while the HUD owns input for slot navigation — the cast buttons stand down so a
## bumper can't fire a spell under the player's feet mid-sort. Movement is NOT gated: focus
## rides the dpad, never the left stick, so the mage keeps walking. Set only via
## set_ui_captured.
var ui_captured := false

## False for the trailing events of a wheel burst — every wheel handler gates on this so
## one physical notch does one thing. Web reports pixel deltas, so a single notch arrives
## as several events spread over a few frames; desktop already sends exactly one.
var wheel_fresh := true

# The window restarts on every wheel event, so even a long browser burst counts once.
const _WHEEL_BURST_MS := 150
var _web := OS.get_name() == "Web"
var _last_wheel_ms := -_WHEEL_BURST_MS

# Actions currently held, for fresh_press. Cleared here rather than by the caller so a release
# still lands while some other node owns input (slot navigation), which would otherwise strand
# an action "held" until the next release.
var _held := {}

## True only for the FIRST press event of `action`, until it is released again.
##
## An analog trigger streams one motion event per value step as it's pulled, and
## InputEvent.is_action_pressed reports true for every one of them past the deadzone — it tests
## the event's own value, it does not track the transition (that's Input.is_action_just_pressed,
## a different path). So a discrete action bound to a trigger fires several times per pull. Any
## action that must happen once per physical press goes through here; ones with their own
## cooldown don't need it. Orthogonal to wheel_fresh, which counts notches within one burst —
## a wheel binding wants both.
func fresh_press(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action):
		return false
	# Only an axis streams. Buttons, keys and wheel notches each send exactly one press event,
	# so holding those to a release we might never see would strand the action for good — they
	# pass straight through, and the guard stays scoped to the thing that actually misbehaves.
	if not event is InputEventJoypadMotion:
		return true
	if _held.has(action):
		return false
	_held[action] = true
	return true

func _input(event: InputEvent) -> void:
	# Runs before any _gui_input or _unhandled_input, so wheel_fresh is already
	# settled for this event by the time a handler reads it.
	if event is InputEventMouseButton and event.pressed \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP
				or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var now := Time.get_ticks_msec()
		wheel_fresh = not _web or now - _last_wheel_ms >= _WHEEL_BURST_MS
		_last_wheel_ms = now
	for action: StringName in _held.keys():
		if event.is_action_released(action):
			_held.erase(action)
	if event is InputEventJoypadButton:
		if event.pressed and _is_gamepad(event.device):
			_set_gamepad(true)
	elif event is InputEventJoypadMotion:
		# Deadzone: resting sticks/triggers report noise; only a deliberate push flips.
		if absf(event.axis_value) > 0.5 and _is_gamepad(event.device):
			_set_gamepad(true)
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_set_gamepad(false)

## True only for a device the engine has a gamepad mapping for.
##
## Linux hands Godot every evdev node that carries EV_ABS plus buttons, so plain HID
## gadgets register as joypads — a Keychron K6 Pro's "System Control" endpoint shows up
## as device 0 with a hat axis, and one media key then reads as a D-pad slam. That flipped
## the game to pad mode: the OS cursor vanished and aim froze to _pad_aim's stick, which on
## a phantom pad never moves. An unmapped device can't drive the game anyway — is_joy_known
## is exactly the promise that button/axis indices match the JoyButton/JoyAxis constants our
## bindings are written against — so ignoring it here costs nothing and stops the hijack.
func _is_gamepad(device: int) -> bool:
	return Input.is_joy_known(device)

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
