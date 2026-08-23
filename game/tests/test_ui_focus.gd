extends Node
## Headless check on the HUD's pad focus ladder: the strip's 12 inventory slots and its
## buttons must chain as ONE 4-wide grid so dpad navigation is deterministic instead of
## Godot's geometric guess, with the edges parked on themselves. Run:
##   godot --headless --path game res://tests/test_ui_focus.tscn

const UI_SCENE := preload("res://gui/ui.tscn")
const COLUMNS := 4

func _ready() -> void:
	var fails: Array[String] = []

	var ui := UI_SCENE.instantiate()
	add_child(ui)

	var nav := []
	nav.append_array(ui.get_node("%Slots").get_children())
	for name_ in ["%BestiaryButton", "%MapButton", "%QuitButton"]:
		nav.append(ui.get_node(name_))

	var expected := GlobalInventory.SIZE + 3
	if nav.size() != expected:
		fails.append("ladder is %d controls, expected %d" % [nav.size(), expected])

	for i in nav.size():
		var c: Control = nav[i]
		if c.focus_mode == Control.FOCUS_NONE:
			fails.append("%s is not focusable" % c.name)
		var col := i % COLUMNS
		_check(fails, nav, i, c.focus_neighbor_left, i - 1 if col > 0 else -1, "left")
		_check(fails, nav, i, c.focus_neighbor_right, i + 1 if col < COLUMNS - 1 else -1, "right")
		_check(fails, nav, i, c.focus_neighbor_top, i - COLUMNS, "top")
		_check(fails, nav, i, c.focus_neighbor_bottom, i + COLUMNS, "bottom")

	# --- line frames: each row wears its own colour, bright only while it is the live line ---
	var frame_x := func(i: int) -> int:
		return int((ui.get_node("%Slots").get_child(i).slot_texture as AtlasTexture).region.position.x)
	for line in GlobalInventory.LINES:
		GlobalInventory.set_line(line)
		for i in GlobalInventory.SIZE:
			var row := GlobalInventory.line_of(i)
			var want: int = (ui.LINE_FRAME_X[row] if row == line else ui.DIM_FRAME_X[row])
			if frame_x.call(i) != want:
				fails.append("slot %d frame is x=%d on line %d, expected x=%d"
						% [i, frame_x.call(i), line, want])
	GlobalInventory.set_line(0)

	# --- focus tooltip: the dpad's stand-in for mouse hover ---
	# Needs a pad and an item carrying modifiers; a bare slot must stay silent, same as the
	# mouse tooltip does.
	var spell := load("res://characters/player/spells/pew/pew1.tres")
	var slot_ui: Control = nav[0]
	if spell == null or spell.get_modifiers().is_empty():
		fails.append("test fixture: pew1 has no modifiers to show")
	else:
		GlobalInventory.slots.at(0).set_item(spell)
		GlobalInput._set_gamepad(true)

		slot_ui.grab_focus()
		if _tip(ui) == null:
			fails.append("no tooltip on a focused filled slot")

		slot_ui.release_focus()
		await get_tree().process_frame
		if _tip(ui) != null:
			fails.append("tooltip outlived focus")

		# Mouse users get Godot's own hover tooltip — ours must not double up.
		GlobalInput._set_gamepad(false)
		slot_ui.grab_focus()
		if _tip(ui) != null:
			fails.append("focus tooltip shown while on mouse")
		slot_ui.release_focus()
		GlobalInventory.slots.at(0).clear_item()

	# --- blurb: text alone raises the tip, and an item with nothing at all stays silent ---
	var mute := SpellResource.new()
	mute.cooldown = 0.0   # the only modifier a bare spell would otherwise carry
	GlobalInput._set_gamepad(true)
	GlobalInventory.slots.at(0).set_item(mute)

	slot_ui.grab_focus()
	if _tip(ui) == null:
		fails.append("no tooltip on an item carrying only a blurb")
	slot_ui.release_focus()
	await get_tree().process_frame

	mute.blurb = ""
	slot_ui.grab_focus()
	if _tip(ui) != null:
		fails.append("tooltip shown for an item with nothing to say")
	slot_ui.release_focus()
	GlobalInventory.slots.at(0).clear_item()
	GlobalInput._set_gamepad(false)

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)

## The live focus tooltip, found by the frame it wears rather than by poking at a private static.
func _tip(ui: Node) -> PanelContainer:
	for c in ui.get_children():
		if c is PanelContainer and c.theme_type_variation == &"TooltipPanel":
			return c
	return null

## A neighbour path must resolve to nav[want] — or back to the control itself when `want` is
## off the ends, which is how the ladder parks focus at an edge.
func _check(fails: Array[String], nav: Array, from: int, path: NodePath, want: int,
		label: String) -> void:
	var src: Control = nav[from]
	var target: Node = nav[want] if want >= 0 and want < nav.size() else src
	if path.is_empty():
		fails.append("%s (%d) has no %s neighbour" % [src.name, from, label])
	elif src.get_node_or_null(path) != target:
		fails.append("%s (%d) %s neighbour is %s, expected %s"
				% [src.name, from, label, path, target.name])
