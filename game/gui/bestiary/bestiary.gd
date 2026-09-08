extends PanelContainer

## The bestiary book: one page per biome, all of them in the book from the start. A page is
## titled with its biome's name and shows that biome's roster as a fixed grid — the grid reserves
## its full 8-column block in the scene whatever the page holds, so the block centres in the same
## spot and a card lands on the same row and column whether its page has twelve enemies or
## twenty-five; a short page just leaves the rows below it empty (commons first, then rares, the
## boss last) plus a completion counter — how many of the biome's enemies
## have been killed vs its total — and the whole-game total sits by the page nav. What fills in
## is the individual cards, which stay locked until their enemy is killed. Lives on the live
## game (no pausing), toggled from the skull button on the HUD strip; Esc or the close button
## dismisses it.

const ENTRY_SCENE := preload("res://gui/bestiary/bestiary_entry.tscn")

var _page := 0
var _pages: Array = []  # Array of {biome, title, ids}, one per biome

func _ready() -> void:
	%PrevPage.pressed.connect(func() -> void: _set_page(_page - 1))
	%NextPage.pressed.connect(func() -> void: _set_page(_page + 1))
	%CloseButton.pressed.connect(hide)
	visibility_changed.connect(_on_visibility_changed)
	# An unlocking kill while the book is open still lands.
	GlobalEvent.bestiary_entry_unlocked.connect(func(_id: StringName) -> void: _refresh_if_open())
	_rebuild()

## Pad paging: dpad left/right turn the page, the only interaction the book has (its cards are
## display-only, and close is the HUD's B/Start). Gated on ui_captured so only a pad-opened book
## pages — the keyboard's arrow keys share ui_left/ui_right and belong to whatever else has them.
## The left stick never gets here (it's bound to movement alone), so the mage keeps walking while
## the book is up. Focus is released while a panel is open, so nothing consumes these first.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not GlobalInput.ui_captured:
		return
	if event.is_action_pressed("ui_left"):
		_set_page(_page - 1)
	elif event.is_action_pressed("ui_right"):
		_set_page(_page + 1)
	else:
		return
	get_viewport().set_input_as_handled()

func _on_visibility_changed() -> void:
	if visible:
		_rebuild()

func _refresh_if_open() -> void:
	if visible:
		_rebuild()

func _rebuild() -> void:
	_pages = GlobalBestiary.pages()
	_set_page(_page)

func _set_page(page: int) -> void:
	var count := maxi(1, _pages.size())
	_page = clampi(page, 0, count - 1)
	var ids: Array = []
	var title := ""
	if _page < _pages.size():
		ids = _pages[_page]["ids"]
		title = _pages[_page]["title"]
	%PageTitle.text = title
	_fill_grid(ids)
	%BiomeCount.text = _fraction(_completion(ids))
	%TotalCount.text = _fraction(_completion(GlobalBestiary.filed_ids()))
	# Arrows dim at the ends instead of hiding, so the nav row never shifts.
	_set_arrow(%PrevPage, _page > 0)
	_set_arrow(%NextPage, _page < count - 1)
	%PageDots.pages = count
	%PageDots.current = _page

## Rebuild the grid for `ids`: one fixed-size card per enemy. Removed synchronously (not just
## queue_free'd) so the grid never lays out the old + new cards together for a frame.
func _fill_grid(ids: Array) -> void:
	var grid: GridContainer = %Entries
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for id in ids:
		var card := ENTRY_SCENE.instantiate()
		grid.add_child(card)
		card.show_entry(id, _kills(id))

func _kills(id: StringName) -> int:
	return GlobalBestiary.kill_count(id)

func _completion(ids: Array) -> Vector2i:
	var done := 0
	for id in ids:
		if _kills(id) > 0:
			done += 1
	return Vector2i(done, ids.size())

func _fraction(v: Vector2i) -> String:
	return "%d/%d" % [v.x, v.y]

func _set_arrow(arrow: TextureButton, enabled: bool) -> void:
	arrow.disabled = not enabled
	arrow.self_modulate.a = 1.0 if enabled else 0.4
