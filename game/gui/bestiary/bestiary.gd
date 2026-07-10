extends PanelContainer

## The bestiary book: one page per discovered biome. A page shows that biome's roster as a
## fixed-cell grid (commons first, then rares, the boss last) plus a completion counter —
## how many of the biome's enemies have been killed vs its total — and the whole-game total
## sits by the page nav. Only discovered biomes get a page (visited, or one of its enemies
## killed), so the book grows as the player explores. Lives on the live game (no pausing),
## toggled from the skull button on the HUD strip; Esc or the close button dismisses it.

const ENTRY_SCENE := preload("res://gui/bestiary/bestiary_entry.tscn")

var _page := 0
var _pages: Array = []  # Array of {biome, color, ids}, one per discovered biome

func _ready() -> void:
	%PrevPage.pressed.connect(func() -> void: _set_page(_page - 1))
	%NextPage.pressed.connect(func() -> void: _set_page(_page + 1))
	%CloseButton.pressed.connect(hide)
	visibility_changed.connect(_on_visibility_changed)
	# Crossing a border or a section-revealing kill while the book is open still lands.
	GlobalEvent.biome_entered.connect(func(_biome: StringName) -> void: _refresh_if_open())
	GlobalEvent.bestiary_entry_unlocked.connect(func(_id: StringName) -> void: _refresh_if_open())
	_rebuild()

func _on_visibility_changed() -> void:
	if visible:
		_rebuild()

func _refresh_if_open() -> void:
	if visible:
		_rebuild()

func _rebuild() -> void:
	_pages = GlobalBestiary.visible_pages()
	_set_page(_page)

func _set_page(page: int) -> void:
	var count := maxi(1, _pages.size())
	_page = clampi(page, 0, count - 1)
	var ids: Array = []
	var boss: StringName = &""
	if _page < _pages.size():
		ids = _pages[_page]["ids"]
		boss = _pages[_page]["boss"]
	_fill_grid(ids)
	# Badge the page with its boss (a living idle loop once slain, a silhouette until then).
	%BossIcon.show_creature(boss, GlobalBestiary.is_unlocked(boss))
	%BiomeCount.text = _fraction(GlobalBestiary.completion(ids))
	%TotalCount.text = _fraction(GlobalBestiary.completion(GlobalBestiary.filed_ids()))
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
		card.show_entry(id)

func _fraction(v: Vector2i) -> String:
	return "%d/%d" % [v.x, v.y]

func _set_arrow(arrow: TextureButton, enabled: bool) -> void:
	arrow.disabled = not enabled
	arrow.self_modulate.a = 1.0 if enabled else 0.4
