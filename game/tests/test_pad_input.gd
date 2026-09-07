extends Node
## Headless checks on the pad's two shared input rules: GlobalInput.fresh_press, the guard that
## turns one physical trigger pull into one action, and the minimap's Y + dpad zoom chord.
## An analog trigger streams a motion event per value step and every one of them
## reports is_action_pressed, so anything without its own cooldown (cast4 on R2) fires several
## times per pull without this. Drives GlobalInput's handlers directly rather than through
## Input.parse_input_event, which defers to the next frame. Run:
##   godot --headless --path game res://tests/test_pad_input.tscn

const MINIMAP := preload("res://gui/minimap/minimap_view.gd")
const MAP_VIEW := preload("res://gui/map/map_view.gd")

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
	var btn := _button(JOY_BUTTON_RIGHT_SHOULDER)   # cast3
	for attempt in 2:
		if not _press(btn, &"cast3"):
			fails.append("cast3 button press %d was swallowed by the axis guard" % attempt)

	# --- the minimap's pad zoom chord: Y + dpad up/down, and nothing else ---
	# Bare, the dpad is slot focus and open-panel input, so the strip only zooms while the
	# modifier is held — never on the arrow keys that share ui_up/ui_down, and never while the
	# UI holds input (there the open full map zooms on its own bare dpad).
	var minimap: Control = MINIMAP.new()
	var dpad_up := _button(JOY_BUTTON_DPAD_UP)
	var dpad_down := _button(JOY_BUTTON_DPAD_DOWN)
	if minimap._pad_chord_dir(dpad_up) != 0:
		fails.append("a bare dpad up zoomed the minimap")
	Input.action_press(&"minimap_zoom_mod")
	if minimap._pad_chord_dir(dpad_up) != -1:
		fails.append("Y + dpad up did not zoom the minimap in")
	if minimap._pad_chord_dir(dpad_down) != 1:
		fails.append("Y + dpad down did not zoom the minimap out")
	var key_up := InputEventKey.new()
	key_up.physical_keycode = KEY_UP
	key_up.pressed = true
	if minimap._pad_chord_dir(key_up) != 0:
		fails.append("the up arrow key zoomed the minimap")
	GlobalInput.set_ui_captured(true)
	if minimap._pad_chord_dir(dpad_up) != 0:
		fails.append("the chord zoomed the minimap while the UI held input")
	GlobalInput.set_ui_captured(false)
	Input.action_release(&"minimap_zoom_mod")
	minimap.free()

	# --- the mage keeps walking while the HUD holds input ---
	# Movement is deliberately ungated (player.get_input_direction), which only holds while slot
	# focus stays off the left stick: ui_* is the dpad and the arrow keys, movement is the stick,
	# and the two never overlap. Bind one to the other and every focus step would also walk the
	# mage, so the split is asserted here instead of assumed.
	const DPAD := [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT,
			JOY_BUTTON_DPAD_RIGHT]
	for action in [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadMotion:
				fails.append("%s rides a stick axis, which also walks the mage" % action)
	for action in [&"up", &"down", &"left", &"right"]:
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton and e.button_index in DPAD:
				fails.append("%s rides the dpad, which also steps slot focus" % action)

	# --- Y pins the open map's centre, and clears a pin that's already there ---
	# The pad has no cursor, so the map pans under a fixed reticle and Y toggles whatever tile
	# sits under it. Driven through the view's own helpers on a bare MapState (pins need no
	# images), so the reticle-to-tile mapping is exercised, not restated.
	GlobalMap.active = MapState.new()
	var map: Control = MAP_VIEW.new()
	map.size = Vector2(101, 57)   # odd on both axes: the true centre lands on a half pixel
	map._state = GlobalMap.active
	for tpp in [1.0, 16.0]:
		map._tpp = tpp
		map._cam = Vector2(320, 160)
		var target := Vector2i(map._screen_to_world(map._centre_px()).floor())
		map._toggle_pin_at(map._screen_to_world(map._centre_px()))
		if GlobalMap.active.pins != [target]:
			fails.append("Y at %s tiles/px pinned %s, expected [%s]"
					% [tpp, GlobalMap.active.pins, target])
		map._toggle_pin_at(map._screen_to_world(map._centre_px()))
		if not GlobalMap.active.pins.is_empty():
			fails.append("Y on an existing pin at %s tiles/px left %s behind"
					% [tpp, GlobalMap.active.pins])
	map.free()
	GlobalMap.active = null

	# Y carries the pin and the strip's zoom modifier and nothing else — the premise both rest
	# on. A third binding here would fire under one of them without any site knowing.
	# ui_select is the exception: Godot puts it on Y by default and only Tree, ItemList and
	# friends consume it. The game has none of those (no .tscn declares one), and a panel is
	# open with focus released, so it reaches nothing. Add one and this needs revisiting.
	for action in InputMap.get_actions():
		if action in [&"map_pin", &"minimap_zoom_mod", &"ui_select"]:
			continue
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton and e.button_index == JOY_BUTTON_Y:
				fails.append("%s also sits on Y, which pins the map" % action)

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

func _button(index: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = index
	e.pressed = true
	return e

func _motion(axis: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
