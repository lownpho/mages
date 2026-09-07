extends Node
## Headless check on the HUD's pad focus ladder: the strip's 4 spell slots, its 8 bag slots
## and its buttons must chain as ONE 4-wide grid so dpad navigation is deterministic instead
## of Godot's geometric guess, with the edges parked on themselves. Run:
##   godot --headless --path game res://tests/test_ui_focus.tscn

const UI_SCENE := preload("res://gui/ui.tscn")
const COLUMNS := 4

func _ready() -> void:
	var fails: Array[String] = []

	var ui := UI_SCENE.instantiate()
	add_child(ui)

	var nav := []
	for group in ["%SpellSlots", "%Bag"]:
		nav.append_array(ui.get_node(group).get_children())
	for name_ in ["%BestiaryButton", "%MapButton", "%QuitButton"]:
		nav.append(ui.get_node(name_))

	var expected := GlobalInventory.SPELL_SLOTS + GlobalInventory.BAG_SIZE + 3
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

	# --- focus tooltip: the dpad's stand-in for mouse hover ---
	# Needs a pad and an item carrying modifiers; a bare slot must stay silent, same as it
	# does under the cursor.
	var spell := load("res://characters/player/spells/pew/pew1.tres")
	var slot_ui: Control = nav[0]
	if spell == null or spell.get_modifiers().is_empty():
		fails.append("test fixture: pew1 has no modifiers to show")
	else:
		GlobalInventory.spell_slots.at(0).set_item(spell)
		GlobalInput._set_gamepad(true)

		slot_ui.grab_focus()
		if _tip(ui) == null:
			fails.append("no tooltip on a focused filled slot")

		slot_ui.release_focus()
		await get_tree().process_frame
		if _tip(ui) != null:
			fails.append("tooltip outlived focus")

		# On mouse and keyboard the tip follows the cursor, not focus, so a focused slot
		# with nothing hovering it must stay silent.
		GlobalInput._set_gamepad(false)
		slot_ui.grab_focus()
		if _tip(ui) != null:
			fails.append("focus tooltip shown while on mouse")
		slot_ui.release_focus()
		GlobalInventory.spell_slots.at(0).clear_item()

	# --- parking spot: clear of the strip, level with the panel of items being described ---
	# The whole point of the custom tip — a per-cursor position would put half of them over the
	# strip they describe. It parks off the panel holding the slot, not off the strip (stretched
	# to the full screen height) or the column (starts at the minimap): either would float the tip
	# above the icons. Every slot in one panel must still land on the same spot.
	if spell != null and not spell.get_modifiers().is_empty():
		var strip: Control = ui.get_node("Strip")
		GlobalInput._set_gamepad(true)
		for group in [["%SpellSlots", "Strip/VBox/SpellsPanel", [0, GlobalInventory.SPELL_SLOTS - 1],
					GlobalInventory.spell_slots],
				["%Bag", "Strip/VBox/BagPanel", [0, GlobalInventory.BAG_SIZE - 1],
					GlobalInventory.bag_slots]]:
			var panel: Control = ui.get_node(group[1])
			var seen := {}
			for index in group[2]:
				group[3].at(index).set_item(spell)
				var c: Control = ui.get_node(group[0]).get_child(index)
				c.grab_focus()
				var tip := _tip(ui)
				if tip == null:
					fails.append("no tooltip on %s" % c.name)
				else:
					seen[tip.global_position] = true
					if tip.global_position.x < strip.global_position.x + strip.size.x:
						fails.append("%s's tip overlaps the strip" % c.name)
					if not is_equal_approx(tip.global_position.y, panel.global_position.y):
						fails.append("%s's tip sits at y %s, not level with %s at y %s"
								% [c.name, tip.global_position.y, panel.name, panel.global_position.y])
				c.release_focus()
				await get_tree().process_frame
				group[3].at(index).clear_item()
			if seen.size() > 1:
				fails.append("%s tips park at %d different positions: %s"
						% [panel.name, seen.size(), seen.keys()])
		GlobalInput._set_gamepad(false)

	# --- blurb: text alone raises the tip, and an item with nothing at all stays silent ---
	var mute := SpellResource.new()
	mute.cooldown = 0.0   # the only modifier a bare spell would otherwise carry
	GlobalInput._set_gamepad(true)
	GlobalInventory.spell_slots.at(0).set_item(mute)

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
	GlobalInventory.spell_slots.at(0).clear_item()
	GlobalInput._set_gamepad(false)

	# --- open panel: the strip keeps a ring, so pad players can see the HUD still owns input ---
	# Focus is released while a panel is up (the dpad belongs to the panel), so the button that
	# opened it wears the focus box as its normal style instead. Mouse play lights nothing.
	var map_button: Button = ui.get_node("%MapButton")
	var ring: StyleBox = map_button.get_theme_stylebox(&"focus")
	for captured in [false, true]:
		GlobalInput.set_ui_captured(captured)
		ui.get_node("%MapPanel").visible = true
		var lit := map_button.get_theme_stylebox(&"normal") == ring
		if lit != captured:
			fails.append("open map ring is %s with ui_captured %s" % [lit, captured])
		ui.get_node("%MapPanel").visible = false
		if map_button.has_theme_stylebox_override(&"normal"):
			fails.append("the ring outlived the open map (ui_captured %s)" % captured)
	GlobalInput.set_ui_captured(false)

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
