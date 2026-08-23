extends Node
## Headless check on GlobalInput.fresh_press, the guard that turns one physical trigger pull into
## one action. An analog trigger streams a motion event per value step and every one of them
## reports is_action_pressed, so anything without its own cooldown (cast4 on R2) fires several
## times per pull without this. Drives GlobalInput's handlers directly rather than through
## Input.parse_input_event, which defers to the next frame. Run:
##   godot --headless --path game res://tests/test_pad_input.tscn

const R2 := JOY_AXIS_TRIGGER_RIGHT   # cast4
const L2 := JOY_AXIS_TRIGGER_LEFT    # cast2

func _ready() -> void:
	var fails: Array[String] = []

	# One pull, ramping past the deadzone: the first step arms it, the rest are the same press.
	var flips := 0
	for value in [0.3, 0.6, 0.9, 1.0]:
		if _press(_motion(R2, value), &"cast4"):
			flips += 1
	if flips != 1:
		fails.append("a single R2 pull counted as %d presses, expected 1" % flips)

	# Still held: a fresh event at full pull must not re-arm.
	if _press(_motion(R2, 1.0), &"cast4"):
		fails.append("R2 re-armed while still held")

	# Release, then pull again — that is a second press.
	_press(_motion(R2, 0.0), &"cast4")
	if not _press(_motion(R2, 1.0), &"cast4"):
		fails.append("R2 did not re-arm after release")

	# Actions are tracked independently: L2 is unaffected by R2 being held.
	if not _press(_motion(L2, 1.0), &"cast2"):
		fails.append("cast2 blocked while cast4 held")
	if _press(_motion(L2, 1.0), &"cast2"):
		fails.append("cast2 re-armed while still held")

	# A release reaching GlobalInput while another node owns input still clears the hold, so
	# the action can't strand itself "held" across a spell of slot navigation.
	GlobalInput.set_ui_captured(true)
	GlobalInput._input(_motion(R2, 0.0))
	GlobalInput.set_ui_captured(false)
	if not GlobalInput.fresh_press(_motion(R2, 1.0), &"cast4"):
		fails.append("release during ui_captured left cast4 stranded")

	# Digital bindings bypass the guard entirely — they send one press event each, so holding
	# them to a release that may never arrive could strand the action. Every press gets through.
	var btn := InputEventJoypadButton.new()
	btn.button_index = JOY_BUTTON_RIGHT_SHOULDER   # cast3
	btn.pressed = true
	for attempt in 2:
		if not _press(btn, &"cast3"):
			fails.append("cast3 button press %d was swallowed by the axis guard" % attempt)

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)

## Feed one event the way the real chain does — GlobalInput._input first (it clears releases),
## then the consumer's fresh_press check.
func _press(event: InputEvent, action: StringName) -> bool:
	GlobalInput._input(event)
	return GlobalInput.fresh_press(event, action)

func _motion(axis: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
