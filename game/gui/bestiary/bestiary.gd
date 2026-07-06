extends PanelContainer

## The bestiary book: a paged grid of entry cards over GlobalBestiary's grouped roster.
## Pages are per biome — a biome always starts a fresh page and overflows onto extra
## pages of its own, and only discovered sections (biome visited, or an enemy of it
## killed) exist at all: the book grows as the player explores. The panel lives on the
## live game (no pausing) and is toggled from the skull button on the HUD strip.

const ENTRIES_PER_PAGE := 8

var _page := 0
var _pages: Array = []  # Array of Array[StringName], ENTRIES_PER_PAGE ids max each

func _ready() -> void:
	%PrevPage.pressed.connect(func() -> void: _set_page(_page - 1))
	%NextPage.pressed.connect(func() -> void: _set_page(_page + 1))
	visibility_changed.connect(_on_visibility_changed)
	# Crossing a border or a section-revealing kill while the book is open still lands.
	GlobalEvent.biome_entered.connect(func(_biome: StringName) -> void: _refresh_if_open())
	GlobalEvent.bestiary_entry_unlocked.connect(func(_id: StringName) -> void: _refresh_if_open())
	_rebuild_pages()
	_set_page(0)

func _on_visibility_changed() -> void:
	if visible:
		_rebuild_pages()
		_set_page(_page)

func _refresh_if_open() -> void:
	if visible:
		_rebuild_pages()
		_set_page(_page)

func _rebuild_pages() -> void:
	_pages.clear()
	for group in GlobalBestiary.visible_grouped_roster():
		for start in range(0, group.size(), ENTRIES_PER_PAGE):
			_pages.append(group.slice(start, start + ENTRIES_PER_PAGE))
	if _pages.is_empty():
		_pages.append([])

func _page_count() -> int:
	return _pages.size()

func _set_page(page: int) -> void:
	_page = clampi(page, 0, _page_count() - 1)
	var ids: Array = _pages[_page]
	var cards := %Entries.get_children()
	for i in cards.size():
		cards[i].show_entry(ids[i] if i < ids.size() else &"")
	# Arrows dim at the ends instead of hiding, so the nav row never shifts.
	_set_arrow(%PrevPage, _page > 0)
	_set_arrow(%NextPage, _page < _page_count() - 1)
	%PageDots.pages = _page_count()
	%PageDots.current = _page

func _set_arrow(arrow: TextureButton, enabled: bool) -> void:
	arrow.disabled = not enabled
	arrow.self_modulate.a = 1.0 if enabled else 0.4
