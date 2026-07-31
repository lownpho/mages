extends Node
## Headless leaderboard-table test: the local sort (including where absent metrics land), the
## dash rendering, column alignment between the header and the rows, the 320x180 fit, and the
## bestiary drill-in reading the browsed player's kill map instead of the local one. Nothing
## here touches Talo — the panel renders whatever show_entries() is handed, which is the whole
## reason that seam exists. Run:
##   godot --headless --path game res://tests/test_leaderboard_ui.tscn

const PANEL := preload("res://gui/leaderboard/leaderboard_panel.tscn")
const VIEWPORT := Vector2(320, 180)

var fails: Array[String] = []


func _ready() -> void:
	# The local bestiary is the thing remote mode must NOT read from, so give it a distinctive
	# slate; the player's real progress is restored before we quit.
	var real_save := GlobalBestiary.to_dict()
	GlobalBestiary.restore({"kills": {"wasp": 99}, "visited": {}})

	var panel: Control = PANEL.instantiate()
	add_child(panel)
	panel.show()
	await get_tree().process_frame
	# Showing it fired a real (logged-out, so failed) refresh that emptied the table; everything
	# below drives show_entries directly.
	await get_tree().process_frame

	panel.show_entries(_rows())
	await get_tree().process_frame

	_check_sorts(panel)
	_check_dashes(panel)
	# Containers lay out deferred, so geometry is only real a frame after the last refill.
	await get_tree().process_frame
	_check_columns(panel)
	_check_fit(panel)
	await _check_drill_in(panel)
	await _check_fixed_slots(panel)

	GlobalBestiary.restore(real_save)
	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


# Four players, each absent from a different board, so every sort has to place a MISSING.
func _rows() -> Array[BoardEntry]:
	var specs := [
		# alias, kills, deaths, ratio, last_death
		["ace", 30.0, 5.0, 3.0, 500.0],
		["bee", 20.0, BoardEntry.MISSING, 9.0, 900.0],
		["cee", BoardEntry.MISSING, 40.0, 1.0, 100.0],
		["dee", 10.0, 20.0, BoardEntry.MISSING, BoardEntry.MISSING],
	]
	var out: Array[BoardEntry] = []
	for spec: Array in specs:
		var row := BoardEntry.new()
		row.player_id = spec[0]
		row.alias = spec[0]
		row.kills = spec[1]
		row.deaths = spec[2]
		row.ratio = spec[3]
		row.last_death = spec[4]
		row.killer = "sproutling"
		row.bestiary = {"sproutling": 7, "fae": 1}
		out.append(row)
	return out


func _aliases(panel: Control) -> Array:
	var out: Array = []
	for row in panel.get_node("%Rows").get_children():
		out.append(row.entry.alias)
	return out


# Each sort is descending on its own metric, and the player absent from that board sinks to the
# bottom rather than floating to the top on a -1 score.
func _check_sorts(panel: Control) -> void:
	var expected := {
		"%SortKills": ["ace", "bee", "dee", "cee"],
		"%SortDeaths": ["cee", "dee", "ace", "bee"],
		"%SortRatio": ["bee", "ace", "cee", "dee"],
		"%SortRecent": ["bee", "ace", "cee", "dee"],
	}
	for button: String in expected:
		panel.get_node(button).pressed.emit()
		var got := _aliases(panel)
		if got != expected[button]:
			fails.append("%s order was %s, expected %s" % [button, str(got), str(expected[button])])
	# Only the active glyph is lit, so the table always says which column it is ordered by.
	panel.get_node("%SortKills").pressed.emit()
	for button: String in ["%SortDeaths", "%SortRatio", "%SortRecent"]:
		if panel.get_node(button).self_modulate.a >= 1.0:
			fails.append("%s still lit while kills is the active sort" % button)
	if panel.get_node("%SortKills").self_modulate.a < 1.0:
		fails.append("active sort glyph is dimmed")


# A metric the player has no board entry for reads as a dash, never as 0 or -1.
func _check_dashes(panel: Control) -> void:
	panel.get_node("%SortKills").pressed.emit()
	for row in panel.get_node("%Rows").get_children():
		for cell: String in ["%Kills", "%Deaths", "%Ratio"]:
			var text: String = row.get_node(cell).text
			if text.begins_with("-") and text != BoardRow.MISSING_TEXT:
				fails.append("%s rendered a missing metric as %s" % [row.entry.alias, text])
	var cee: Control = panel.get_node("%Rows").get_child(3)
	if cee.get_node("%Kills").text != BoardRow.MISSING_TEXT:
		fails.append("absent kills rendered as '%s'" % cee.get_node("%Kills").text)
	# Kills read as bestiary completion, so the column carries its denominator: the count of every
	# enemy filed in the book, the same total that book shows in its own corner.
	var filed := GlobalBestiary.filed_ids().size()
	var top_kills: String = panel.get_node("%Rows").get_child(0).get_node("%Kills").text
	if top_kills != "30/%d" % filed:
		fails.append("kills should read '30/%d' as completion, got '%s'" % [filed, top_kills])
	# The ratio column is the only one with a decimal, and it must keep exactly one.
	if panel.get_node("%Rows").get_child(0).get_node("%Ratio").text != "3.0":
		fails.append("ratio formatting: " + panel.get_node("%Rows").get_child(0).get_node("%Ratio").text)


# The header glyphs and the row cells are authored in two different scenes, so their column
# widths can drift apart. Pin them together: every header cell must start where its column does.
func _check_columns(panel: Control) -> void:
	var head: Array = panel.get_node("%Head").get_children()
	var cells: Array = panel.get_node("%Rows").get_child(0).get_node("Cells").get_children()
	if head.size() != cells.size():
		fails.append("header has %d cells, rows have %d" % [head.size(), cells.size()])
		return
	for i in head.size():
		if not is_equal_approx(head[i].position.x, cells[i].position.x):
			fails.append("column %d: header at x=%s, row cell at x=%s"
					% [i, head[i].position.x, cells[i].position.x])
	# A metric's header glyph is centred in its cell, so its numbers must be centred too or the
	# glyph floats off to one side of the column it labels — which is the only thing saying what
	# the number means.
	for i in [2, 3, 4]:
		if cells[i].horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
			fails.append("%s is not centred under its header glyph" % cells[i].name)
		# An icon-only Button places its icon by icon_alignment, NOT alignment — the default
		# (left) parks the glyph at the cell edge, adrift from the column it labels.
		if head[i].icon_alignment != HORIZONTAL_ALIGNMENT_CENTER:
			fails.append("%s glyph is not centred in its cell" % head[i].name)
	# clip_text hides overflow silently, so assert the longest allowed alias actually fits
	# (auth_dialog caps names at 20 characters).
	_check_fits(cells[1], "MMMMMMMMMMMMMMMMMMMM", "a 20-char alias")
	# The completion fraction grows with the roster; make sure the column still holds it, with
	# room for the roster reaching three digits.
	_check_fits(cells[2], "100/100", "a full completion fraction")


func _check_fits(cell: Label, sample: String, what: String) -> void:
	var width := cell.get_theme_font(&"font").get_string_size(
			sample, HORIZONTAL_ALIGNMENT_LEFT, -1, cell.get_theme_font_size(&"font_size")).x
	if width > cell.size.x:
		fails.append("%s needs %spx but the %s column is %spx" % [what, width, cell.name, cell.size.x])


func _check_fit(panel: Control) -> void:
	var table: Control = panel.get_node("%Table")
	if table.size.x > VIEWPORT.x or table.size.y > VIEWPORT.y:
		fails.append("table is %s, larger than the %s viewport" % [table.size, VIEWPORT])
	# Fractional offsets blur pixel art on an integer-scaled viewport.
	for node in [table, panel.get_node("%Rows"), panel.get_node("%Head")]:
		if node.position != node.position.round() or node.size != node.size.round():
			fails.append("%s is off the pixel grid: pos %s size %s"
					% [node.name, node.position, node.size])
	if panel.get_node("%Rows").get_child_count() > panel.MAX_ROWS:
		fails.append("more than MAX_ROWS lines rendered")


# Drilling into a line must render THAT player's kills. The local slate has wasp 99 and no
# sproutling, the browsed map has sproutling 7 and no wasp — so a leak shows up either way.
func _check_drill_in(panel: Control) -> void:
	var bestiary: Control = panel.get_node("%Bestiary")
	panel.get_node("%Rows").get_child(0).pressed.emit()
	await get_tree().process_frame
	if not bestiary.visible:
		fails.append("clicking a line did not open the bestiary")
	if panel.get_node("%Table").visible:
		fails.append("table still visible behind the drill-in")
	# Going back is a button, not just an Esc: the book is somewhere you navigated INTO.
	if not bestiary.get_node("%BackButton").visible:
		fails.append("no back button in the drill-in")
	if bestiary.get_node("%CloseButton").visible:
		fails.append("close button still offered in the drill-in")
	var counts := _grid_counts(bestiary)
	if counts.get("sproutling") != "7":
		fails.append("drill-in shows sproutling '%s', expected the browsed 7"
				% counts.get("sproutling"))
	if counts.get("wasp", "") != "":
		fails.append("drill-in leaked the local wasp count: '%s'" % counts.get("wasp"))

	bestiary.get_node("%BackButton").pressed.emit()
	await get_tree().process_frame
	if bestiary.visible or not panel.get_node("%Table").visible:
		fails.append("back button did not return to the table")
	# Back in local mode the book is its own top-level panel again.
	if not bestiary.get_node("%CloseButton").visible or bestiary.get_node("%BackButton").visible:
		fails.append("nav buttons not restored to local mode")


# Two things that must not drift: the book and the table are the same panel size (they are the
# same screen, one level apart), and a bestiary slot is a FIXED cell no art can resize. Creatures
# draw at native size, so without a hard cap the first oversized enemy reflows the whole grid.
const OVERSIZED := Vector2i(64, 64)


func _check_fixed_slots(panel: Control) -> void:
	var table: Control = panel.get_node("%Table")
	var bestiary: Control = panel.get_node("%Bestiary")
	if table.size != bestiary.size:
		fails.append("table is %s but the book is %s — they should be one panel size"
				% [table.size, bestiary.size])

	panel.get_node("%Rows").get_child(0).pressed.emit()
	await get_tree().process_frame
	var grid: GridContainer = bestiary.get_node("%Entries")
	if grid.get_child_count() == 0:
		fails.append("no cards to measure")
		return
	var card: Control = grid.get_child(0)
	var was_card := card.size
	var was_cell: Vector2 = card.get_node("%Icon").size
	# Force art far larger than the cell into one card; nothing may grow, and the grid must not
	# reflow around it.
	var was_grid := grid.size
	var image := Image.create(OVERSIZED.x, OVERSIZED.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.MAGENTA)
	card.get_node("%Icon").texture = ImageTexture.create_from_image(image)
	await get_tree().process_frame
	await get_tree().process_frame
	if card.size != was_card:
		fails.append("a %s icon resized its slot: %s -> %s" % [OVERSIZED, was_card, card.size])
	if card.get_node("%Icon").size != was_cell:
		fails.append("a %s icon resized its cell: %s -> %s"
				% [OVERSIZED, was_cell, card.get_node("%Icon").size])
	if grid.size != was_grid:
		fails.append("a %s icon reflowed the grid: %s -> %s" % [OVERSIZED, was_grid, grid.size])
	if not card.get_node("%Icon").clip_contents:
		fails.append("the cell does not clip, so oversized art bleeds into its neighbours")
	panel.get_node("%Bestiary").hide()


func _grid_counts(bestiary: Control) -> Dictionary:
	var out: Dictionary = {}
	for card in bestiary.get_node("%Entries").get_children():
		out[String(card.enemy_id)] = card.get_node("%Count").text
	return out
