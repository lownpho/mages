extends Node
## Headless check on the controls page: every prompt it shows exists in the input-prompt
## atlas, and every row fits the panel the HUD gives it. Both are silent failures otherwise —
## a name the atlas dropped leaves a hole, and an over-long row just clips off the right edge
## — and neither shows up in any other test. Run:
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
	# The pages are centred in this area, so the area — not a table's own width — is what a
	# row has to fit into.
	var area: Control = panel.get_node("%RowsArea")
	var pages := area.get_children()

	if pages.is_empty():
		fails.append("no pages")

	# --- every prompt resolves ---
	# KeyPrompt leaves its texture null when the atlas has no region under that name, which on
	# the page reads as a row that quietly lost an icon.
	for page in pages:
		for prompt in page.find_children("*", "KeyPrompt", true, false):
			if prompt.texture == null:
				fails.append("page '%s' asks for the icon '%s', which the atlas has no region for"
						% [page.name, prompt.icon])
	# The strip button that opens the page is looked up by name too, in ui.gd.
	if KeyIcons.texture(&"hud_controls") == null:
		fails.append("no hud_controls icon for the strip button")
	if ui.get_node("%ControlsButton").icon == null:
		fails.append("the strip button never got its icon")

	# --- every row fits, on every page ---
	# The panel is only 258px wide, so a third of it is not much room for a description and a
	# long line is the easy way to break this page. Every table shares the panel's width, so
	# they all divide into the same thirds.
	panel.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	for i in pages.size():
		panel._set_page(i)
		await get_tree().process_frame
		var page: Control = pages[i]
		var used := 0.0
		for child in page.get_children():
			var wide: float = (child as Control).get_combined_minimum_size().x
			if wide > area.size.x:
				fails.append("page '%s': a row wants %dpx of the %dpx the page has"
						% [page.name, wide, area.size.x])
			# A table's cells are three equal columns in row-major order — keyboard prompts,
			# pad prompts, description — and every table on the page has to agree on where
			# those columns fall, or the page reads as a wobble rather than as a table.
			# Section headings and spacers are not tables and have no columns.
			if child is GridContainer:
				var columns: Array[float] = []
				for c in child.get_child_count():
					var cell: Control = child.get_child(c)
					if c < child.columns:
						columns.append(cell.size.x)
					elif absf(cell.size.x - columns[c % child.columns]) > 1.0:
						fails.append("page '%s': '%s' is %dpx in a %dpx column"
								% [page.name, cell.name, cell.size.x,
										columns[c % child.columns]])
				# A width that does not divide by three spreads the odd pixel, not a column.
				if columns.max() - columns.min() > 1.0:
					fails.append("page '%s': the '%s' columns are %s wide, not equal thirds"
							% [page.name, child.name, columns])
			used += (child as Control).get_combined_minimum_size().y
		used += page.get_theme_constant(&"separation") * maxi(0, page.get_child_count() - 1)
		if used > area.size.y:
			fails.append("page '%s': %d rows want %dpx of the %dpx the page has"
					% [page.name, page.get_child_count(), used, area.size.y])

	# --- one page is up at a time, and it is the one the title names ---
	panel._set_page(0)
	var shown := 0
	for page in pages:
		if (page as Control).visible:
			shown += 1
	if shown != 1:
		fails.append("%d pages visible at once" % shown)
	if panel.get_node("%PageTitle").text != String(pages[0].name):
		fails.append("the title says '%s' on the '%s' page"
				% [panel.get_node("%PageTitle").text, pages[0].name])

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
