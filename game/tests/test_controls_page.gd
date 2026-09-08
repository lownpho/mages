extends Node
## Headless check on the controls page: every prompt it asks for exists in the input-prompt
## atlas, and every row it builds fits the panel the HUD gives it. Both are silent failures
## otherwise — a typo'd icon name leaves a hole, and an over-long row just clips off the
## right edge — and neither shows up in any other test. Run:
##   godot --headless --path game res://tests/test_controls_page.tscn

const UI_SCENE := preload("res://gui/ui.tscn")

func _ready() -> void:
	var fails: Array[String] = []

	# Headless gives the root viewport whatever size it likes; the page is only ever seen at
	# the game's own 320x180, and "does a row fit" is a question about that size alone.
	get_window().size = Vector2i(320, 180)
	var ui := UI_SCENE.instantiate()
	add_child(ui)
	var panel: PanelContainer = ui.get_node("%ControlsPanel")
	var rows: VBoxContainer = panel.get_node("%Rows")
	# The table is centred in this area, so the area — not the table's own width — is what a
	# row has to fit into.
	var area: Control = panel.get_node("%RowsArea")
	var pages: Array = panel.PAGES

	if pages.is_empty():
		fails.append("no pages")

	# --- every prompt resolves ---
	for page in pages:
		for section in page["sections"]:
			for row in section["rows"]:
				for name_ in row["keys"] + row["pad"]:
					if not KeyIcons.REGIONS.has(StringName(name_)):
						fails.append("page '%s' asks for the icon '%s', which the atlas has no region for"
								% [page["title"], name_])
	# The strip button that opens the page is looked up by name too, in ui.gd.
	if KeyIcons.texture(&"hud_controls") == null:
		fails.append("no hud_controls icon for the strip button")
	if ui.get_node("%ControlsButton").icon == null:
		fails.append("the strip button never got its icon")

	# --- every row fits, on every page ---
	# The panel is only 258px wide and the description column is whatever is left after the
	# two prompt columns, so a long line is the easy way to break this page.
	panel.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	for i in pages.size():
		panel._set_page(i)
		await get_tree().process_frame
		var used := 0.0
		for child in rows.get_children():
			var wide: float = (child as Control).get_combined_minimum_size().x
			if wide > area.size.x:
				fails.append("page '%s': a row wants %dpx of the %dpx the page has"
						% [pages[i]["title"], wide, area.size.x])
			# Each prompt has to fit its column, or it shoves the columns to its right out of
			# line on that row alone. Headings and spacers have no columns to fit.
			if child.get_child_count() == 3:
				var columns := [panel.KEY_COL, panel.PAD_COL]
				for c in columns.size():
					var cell: Control = child.get_child(c)
					var want: float = cell.get_combined_minimum_size().x
					if want > columns[c]:
						fails.append("page '%s': a %dpx prompt in the %dpx column by '%s'"
								% [pages[i]["title"], want, columns[c], child.get_child(2).text])
			used += (child as Control).get_combined_minimum_size().y
		used += rows.get_theme_constant(&"separation") * maxi(0, rows.get_child_count() - 1)
		if used > area.size.y:
			fails.append("page '%s': %d rows want %dpx of the %dpx the page has"
					% [pages[i]["title"], rows.get_child_count(), used, area.size.y])

	# --- paging clamps instead of wrapping, and the arrows say so ---
	panel._set_page(-1)
	if panel._page != 0:
		fails.append("paging past the front landed on %d" % panel._page)
	if not panel.get_node("%PrevPage").disabled:
		fails.append("the back arrow is live on the first page")
	panel._set_page(pages.size())
	if panel._page != pages.size() - 1:
		fails.append("paging past the end landed on %d" % panel._page)
	if not panel.get_node("%NextPage").disabled:
		fails.append("the forward arrow is live on the last page")

	# --- the page is one of the strip's overlays: opening it closes the others ---
	panel.visible = false
	ui.get_node("%BestiaryPanel").visible = true
	ui.get_node("%ControlsButton").pressed.emit()
	if ui.get_node("%BestiaryPanel").visible:
		fails.append("opening the controls page left the bestiary up")
	if not panel.visible:
		fails.append("the strip button did not open the controls page")

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
