extends Node
## Headless check on the grimoire's grid — the bestiary's layout rules, applied to spells. It is a
## FIXED grid: it reserves a full page's block in the scene rather than shrinking to what the page
## holds, so a card keeps its row and column however full its page is. Cells are fixed, so an icon
## can never push its slot wider. And every shipped spell is on exactly one page, drawn in full once
## learned and as a silhouette until then. All of it is silent at 320x180 when it breaks. Run:
##   godot --headless --path game res://tests/test_grimoire_page.tscn

const UI_SCENE := preload("res://gui/ui.tscn")
const CELL := Vector2(18, 18)  # grimoire_entry.tscn's fixed cell

func _ready() -> void:
	var fails: Array[String] = []

	# Every other spell learned, so both card states show up on the page.
	var real_save := GlobalGrimoire.to_dict()
	var entries := GlobalGrimoire.entries()
	var half: Array = []
	for i in range(0, entries.size(), 2):
		half.append(entries[i])
	GlobalGrimoire.restore({"learned": half})

	# Headless picks its own window size; the book is only ever seen at the game's 320x180.
	get_window().size = Vector2i(320, 180)
	var ui := UI_SCENE.instantiate()
	add_child(ui)
	var panel: PanelContainer = ui.get_node("%GrimoirePanel")
	var grid: GridContainer = panel.get_node("%Entries")
	var nav: Control = panel.get_node("%PrevPage").get_parent()
	panel.visible = true
	await get_tree().process_frame
	await get_tree().process_frame

	var h_sep := grid.get_theme_constant(&"h_separation")
	var v_sep := grid.get_theme_constant(&"v_separation")

	# --- the reserved block is exactly one full page of cards ---
	var rows: int = panel.rows
	var per_page := grid.columns * rows
	var reserved := grid.custom_minimum_size
	var full_page := Vector2(grid.columns * CELL.x + (grid.columns - 1) * h_sep, rows * CELL.y + (rows - 1) * v_sep)
	if reserved != full_page:
		fails.append("a page of %d x %d cards is %s, but the grid reserves %s"
				% [grid.columns, rows, full_page, reserved])
	var page_count := maxi(1, ceili(float(entries.size()) / per_page))
	if panel.get_node("%PageDots").pages != page_count:
		fails.append("%d dots for %d pages" % [panel.get_node("%PageDots").pages, page_count])

	var shown: Array[StringName] = []
	var origin := Vector2.INF
	var inside := panel.get_global_rect().grow(-3.0)  # the Margin
	for i in page_count:
		panel._set_page(i)
		await get_tree().process_frame
		var cards := grid.get_children()
		if cards.size() > per_page:
			fails.append("page %d holds %d cards, more than a page's %d" % [i, cards.size(), per_page])

		# --- the block does not resize to the page, and so does not move when it is centred ---
		if grid.size != reserved:
			fails.append("page %d: the grid is %s, not the %s the scene reserves" % [i, grid.size, reserved])
		if origin == Vector2.INF:
			origin = grid.global_position
		elif grid.global_position != origin:
			fails.append("page %d: the block sits at %s, page 0's at %s" % [i, grid.global_position, origin])

		# --- the whole block fits the panel, clear of the nav ---
		# Measured against the panel, not the body: the body is anchored, so an over-tall block grows
		# it rather than clipping, and would still "fit" its parent.
		var block := grid.get_global_rect()
		if not inside.encloses(block):
			fails.append("page %d: the block %s runs outside the panel %s" % [i, block, inside])
		if block.intersects(nav.get_global_rect()):
			fails.append("page %d: the block runs into the page nav" % i)

		for c in cards.size():
			var card: Control = cards[c]
			shown.append(card.id)
			# --- fixed cells, filled row-major from the block's corner ---
			if card.size != CELL:
				fails.append("page %d: the %s card is %s, not the fixed %s" % [i, card.id, card.size, CELL])
			var want := Vector2((c % grid.columns) * (CELL.x + h_sep), (c / grid.columns) * (CELL.y + v_sep))
			if card.position != want:
				fails.append("page %d: card %d sits at %s, want %s" % [i, c, card.position, want])
			# --- an icon in every card, a silhouette exactly while the spell is unlearned ---
			var icon: TextureRect = card.get_node("%Icon")
			if icon.texture == null:
				fails.append("page %d: no icon for %s" % [i, card.id])
			var silhouette := icon.material != null
			if silhouette == GlobalGrimoire.is_learned(card.id):
				fails.append("page %d: %s is %s but %s" % [i, card.id,
						"learned" if GlobalGrimoire.is_learned(card.id) else "not learned",
						"a silhouette" if silhouette else "drawn in full"])
			if card.find_children("*", "Label").size() > 0:
				fails.append("page %d: the %s card carries text" % [i, card.id])

	# --- every shipped spell on exactly one page, in book order ---
	if shown != entries:
		fails.append("the pages show %d cards %s, want the %d entries in book order"
				% [shown.size(), str(shown), entries.size()])

	var learned := GlobalGrimoire.completion(entries)
	if panel.get_node("%TotalCount").text != "%d/%d" % [learned.x, learned.y]:
		fails.append("the count reads '%s', want %d/%d" % [panel.get_node("%TotalCount").text, learned.x, learned.y])

	# --- a pickup while the book is open fills its card straight away ---
	panel._set_page(0)
	var locked: Control = null
	for card in grid.get_children():
		if not GlobalGrimoire.is_learned(card.id):
			locked = card
			break
	if locked == null:
		fails.append("test fixture: no locked spell on the first page")
	else:
		var id: StringName = locked.id
		var slot := GlobalInventory.Slot.new(GlobalInventory.ItemType.BAG)
		slot.item = GlobalGrimoire.load_spell(id)
		GlobalEvent.item_picked_up.emit(slot)
		for card in grid.get_children():
			if card.id == id and card.get_node("%Icon").material != null:
				fails.append("picking up %s left its open card a silhouette" % id)

	# --- paging clamps instead of wrapping, and the arrows say so ---
	panel._set_page(-1)
	if panel._page != 0:
		fails.append("paging past the front landed on %d" % panel._page)
	if not panel.get_node("%PrevPage").disabled:
		fails.append("the back arrow is live on the first page")
	panel._set_page(page_count)
	if panel._page != page_count - 1:
		fails.append("paging past the end landed on %d" % panel._page)
	if not panel.get_node("%NextPage").disabled:
		fails.append("the forward arrow is live on the last page")

	# --- the book is one of the strip's overlays: opening it closes the others ---
	panel.visible = false
	ui.get_node("%BestiaryPanel").visible = true
	ui.get_node("%GrimoireButton").pressed.emit()
	if ui.get_node("%BestiaryPanel").visible:
		fails.append("opening the grimoire left the bestiary up")
	if not panel.visible:
		fails.append("the strip button did not open the grimoire")

	GlobalGrimoire.restore(real_save)
	GlobalGrimoire._save()

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
