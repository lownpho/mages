extends Node
## Headless check on the bestiary's grid: it is a FIXED grid. The block is centred in the body,
## but it reserves its whole size in the scene rather than shrinking to the page, so the centring
## resolves to the same place every time and a card keeps its row and column however few enemies
## the page holds. Every one of those failures is silent at 320x180 — a grid that shrinks to fit
## still looks like a grid, it just walks about as you page — and so is a card whose art pushed
## its cell wider, or a page whose rows run off the bottom. Run:
##   godot --headless --path game res://tests/test_bestiary_page.tscn

const UI_SCENE := preload("res://gui/ui.tscn")
const CELL := Vector2(26, 34)  # bestiary_entry.tscn's fixed cell

func _ready() -> void:
	var fails: Array[String] = []

	# Headless picks its own window size; the book is only ever seen at the game's 320x180,
	# and "does the grid fit" is a question about that size alone.
	get_window().size = Vector2i(320, 180)
	var ui := UI_SCENE.instantiate()
	add_child(ui)
	var panel: PanelContainer = ui.get_node("%BestiaryPanel")
	var grid: GridContainer = panel.get_node("%Entries")
	var nav: Control = panel.get_node("%PrevPage").get_parent()
	panel.visible = true
	await get_tree().process_frame
	await get_tree().process_frame

	var pages: Array = panel._pages
	if pages.is_empty():
		fails.append("no pages")

	# Where the centred block resolves to, and how big it is. Both are measured off the first
	# page and then demanded of every other one — the block is allowed to sit wherever the
	# centring puts it, as long as it is the SAME wherever.
	var origin := Vector2.INF
	var block := Vector2.ZERO
	var reserved: Vector2 = grid.custom_minimum_size

	for i in pages.size():
		panel._set_page(i)
		await get_tree().process_frame
		var title: String = pages[i]["title"]
		var cards := grid.get_children()
		if cards.size() != (pages[i]["ids"] as Array).size():
			fails.append("page '%s' shows %d cards for %d enemies"
					% [title, cards.size(), (pages[i]["ids"] as Array).size()])
		if cards.is_empty():
			continue

		# --- the block does not resize to the page, and so does not move when it is centred ---
		# A page that outgrows the reserved rows pushes the grid bigger, and the centring shifts
		# every other page's cards to make room for it.
		if grid.size != reserved:
			fails.append("page '%s': the grid is %s, not the %s the scene reserves"
					% [title, grid.size, reserved])
		if origin == Vector2.INF:
			origin = grid.position
			block = grid.size
		if grid.position != origin:
			fails.append("page '%s': the block centres at %s, page 0 at %s"
					% [title, grid.position, origin])
		if grid.size != block:
			fails.append("page '%s': the block is %s, page 0 is %s" % [title, grid.size, block])

		# --- fixed cells: art is cropped to the cell, never allowed to resize the slot ---
		for card: Control in cards:
			if card.size != CELL:
				fails.append("page '%s': the '%s' card is %s, not the fixed %s"
						% [title, card.name, card.size, CELL])

		# --- the whole reserved block fits the room the panel gives it ---
		# Measured against the panel and its two rows, not against the body Control: the body
		# is anchored, so it is grown by an over-tall block rather than clipping it, and a grid
		# that has swallowed the page nav still "fits" its parent.
		var rows := ceili(grid.size.y / (CELL.y + grid.get_theme_constant(&"v_separation")))
		var block_rect := grid.get_global_rect()
		var inside := panel.get_global_rect().grow(-3.0)  # the Margin
		if block_rect.position.x < inside.position.x or block_rect.end.x > inside.end.x:
			fails.append("page '%s': %d columns want %dpx of the %dpx the panel has"
					% [title, grid.columns, grid.size.x, inside.size.x])
		if block_rect.position.y < inside.position.y or block_rect.end.y > inside.end.y:
			fails.append("page '%s': %d rows want %dpx of the %dpx the panel has"
					% [title, rows, grid.size.y, inside.size.y])
		if block_rect.intersects(nav.get_global_rect()):
			fails.append("page '%s': %d rows run into the page nav" % [title, rows])

		# --- cards fill row-major from the block's corner, one column step at a time ---
		# Card positions are the grid's own space, so the corner is (0, 0) here; where that
		# corner lands on the panel is the block-position check above.
		for c in mini(cards.size(), grid.columns + 1):
			@warning_ignore("integer_division") # Whole counts and grid indices intentionally truncate.
			var want := Vector2(
					(c % grid.columns) * (CELL.x + grid.get_theme_constant(&"h_separation")),
					(c / grid.columns) * (CELL.y + grid.get_theme_constant(&"v_separation")))
			if (cards[c] as Control).position != want:
				fails.append("page '%s': card %d sits at %s, want %s"
						% [title, c, (cards[c] as Control).position, want])

		# --- every card resolved an icon: a missing one leaves a hole, not an error ---
		for card in cards:
			if card.get_node("%Icon").texture == null:
				fails.append("page '%s': no icon for '%s'" % [title, card.enemy_id])

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

	# --- the book is one of the strip's overlays: opening it closes the others ---
	panel.visible = false
	ui.get_node("%ControlsPanel").visible = true
	ui.get_node("%BestiaryButton").pressed.emit()
	if ui.get_node("%ControlsPanel").visible:
		fails.append("opening the bestiary left the controls page up")
	if not panel.visible:
		fails.append("the strip button did not open the bestiary")

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
