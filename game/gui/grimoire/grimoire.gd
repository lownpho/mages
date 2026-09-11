extends PanelContainer

## The grimoire, laid out like the bestiary: a fixed grid of cards, one per spell the game ships —
## its icon once it has been picked up, a gray silhouette until then — and the learned vs total
## count by the page nav. No names, tiers or categories: the icons are the whole read. The grid
## reserves a full page's block in the scene, so a card keeps its row and column however full its
## page is; a page is `rows` rows of the grid's columns, and pages only exist to hold the overflow.
## Lives on the live game (no pausing), toggled from the book button on the HUD strip; Esc or the
## close button dismisses it.

const ENTRY_SCENE := preload("res://gui/grimoire/grimoire_entry.tscn")

## Rows per page; with %Entries.columns, a page's capacity. %Entries' reserved size in the scene is
## that many rows of cards — test_grimoire_page.gd checks the two agree.
@export var rows := 6

var _page := 0

func _ready() -> void:
	%PrevPage.pressed.connect(func() -> void: _set_page(_page - 1))
	%NextPage.pressed.connect(func() -> void: _set_page(_page + 1))
	%CloseButton.pressed.connect(hide)
	visibility_changed.connect(_refresh_if_open)
	# A pickup while the book is open still lands.
	GlobalEvent.grimoire_entry_learned.connect(func(_id: StringName) -> void: _refresh_if_open())
	_set_page(0)

## Pad paging — same gate as the bestiary's: only a pad-opened book reads the dpad, since the
## keyboard's arrows share ui_left/ui_right and belong to whatever else has them. The left stick
## never reaches here (movement only), so the mage keeps walking while the book is up.
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

func _refresh_if_open() -> void:
	if visible:
		_set_page(_page)

func _set_page(page: int) -> void:
	var entries := GlobalGrimoire.entries()
	var per_page: int = %Entries.columns * rows
	var count := maxi(1, ceili(float(entries.size()) / per_page))
	_page = clampi(page, 0, count - 1)
	_fill_grid(entries.slice(_page * per_page, (_page + 1) * per_page))
	var learned := GlobalGrimoire.completion(entries)
	%TotalCount.text = "%d/%d" % [learned.x, learned.y]
	# Arrows dim at the ends instead of hiding, so the nav row never shifts.
	_set_arrow(%PrevPage, _page > 0)
	_set_arrow(%NextPage, _page < count - 1)
	%PageDots.pages = count
	%PageDots.current = _page

## Rebuild the grid for `ids`: one fixed-size card per spell. Removed synchronously (not just
## queue_free'd) so the grid never lays out the old + new cards together for a frame.
func _fill_grid(ids: Array) -> void:
	var grid: GridContainer = %Entries
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for id in ids:
		var card := ENTRY_SCENE.instantiate()
		grid.add_child(card)
		card.show_entry(id, GlobalGrimoire.is_learned(id))

func _set_arrow(arrow: TextureButton, enabled: bool) -> void:
	arrow.disabled = not enabled
	arrow.self_modulate.a = 1.0 if enabled else 0.4
