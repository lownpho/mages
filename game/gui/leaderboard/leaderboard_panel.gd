extends Control

## The boards as ONE sortable table rather than a tab per metric. Every metric is its own Talo
## leaderboard, so the panel fetches all four on open and unions them by player id into
## BoardEntry rows; every sort after that is local, so changing the order costs no request and
## the table never blinks. Clicking a line opens the bestiary on that player's kill map — it
## rides along on their unique_kills entry, so drilling in costs nothing either.

const MAX_ROWS := 8
const ROW_SCENE := preload("res://gui/leaderboard/board_row.tscn")
## Dim for the sort glyphs that aren't active. Higher than the bestiary arrows' 0.4: those mean
## "unavailable", these still have to be legible, since a glyph is how you read its column.
const GLYPH_DIM := 0.6
## Separates the header from the body. Dark enough to read as a rule rather than a row.
const DIVIDER_COLOR := Palette.TEAL_DARK

@onready var _table: PanelContainer = %Table
@onready var _rows: VBoxContainer = %Rows
@onready var _bestiary: PanelContainer = %Bestiary
@onready var _emblem: TextureRect = %Emblem
@onready var _sort_buttons: Array[Button] = [
	%SortKills, %SortDeaths, %SortRatio, %SortRecent,
]

var _entries: Array[BoardEntry] = []
var _sort := BoardEntry.Sort.KILLS
# Distinguishes overlapping refreshes: a fetch resolving after the panel was closed and
# reopened must not fill the newer open's table.
var _refresh_id := 0


func _ready() -> void:
	%Divider.color = DIVIDER_COLOR
	%CloseButton.pressed.connect(hide)
	for i in _sort_buttons.size():
		_sort_buttons[i].pressed.connect(_on_sort.bind(i))
	# The bestiary dismisses itself (its back button, Esc), and that's the whole return path: the
	# table shows whenever the book isn't up. Dropping it back to local mode belongs here too,
	# or a book closed by its own button stays stuck on the browsed player.
	_bestiary.visibility_changed.connect(func() -> void:
		_table.visible = not _bestiary.visible
		if not _bestiary.visible:
			_bestiary.show_local())
	visibility_changed.connect(func() -> void:
		if visible:
			_show_table()
			_refresh())
	_apply_sort_glyphs()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	accept_event()
	# Esc unwinds one level at a time: the book back to the table, the table off the screen.
	if _bestiary.visible:
		_show_table()
	else:
		hide()


## Render an explicit row set. The fetch calls this once its four requests have landed; the
## preview and test scenes call it with fabricated rows, which is the only way to exercise the
## table without an account — nothing here touches the network.
func show_entries(entries: Array[BoardEntry]) -> void:
	_entries = entries
	_fill()


func _show_table() -> void:
	_bestiary.hide()  # its visibility_changed brings the table back and clears remote mode
	_table.show()


func _open_bestiary(entry: BoardEntry) -> void:
	_bestiary.show_remote(entry.bestiary)
	_bestiary.show()


func _on_sort(index: int) -> void:
	_sort = index as BoardEntry.Sort
	_apply_sort_glyphs()
	_fill()


# Each glyph wears its column's hue, which is the only thing tying a number back to its header,
# so the dim for an inactive sort is alpha only — never a colour change.
func _apply_sort_glyphs() -> void:
	for i in _sort_buttons.size():
		var color := BoardEntry.COLORS[i]
		color.a = 1.0 if i == _sort else GLYPH_DIM
		_sort_buttons[i].self_modulate = color


func _fill() -> void:
	# Removed synchronously rather than just queue_free'd, so the list never lays out the old
	# and new lines together for a frame.
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var me := GlobalLeaderboard.username()
	var ranked := _entries.duplicate()
	ranked.sort_custom(_before)
	for i in mini(ranked.size(), MAX_ROWS):
		var row: BoardRow = ROW_SCENE.instantiate()
		_rows.add_child(row)  # in the tree first: bind() reads its colours off the theme
		row.bind(ranked[i], i + 1, ranked[i].alias == me)
		row.pressed.connect(_open_bestiary.bind(ranked[i]))


# Descending on the active metric, alias alphabetically to break ties. MISSING sits below every
# real score, so players absent from the sorted board fall to the bottom instead of the top.
func _before(a: BoardEntry, b: BoardEntry) -> bool:
	var a_value := a.metric(_sort)
	var b_value := b.metric(_sort)
	if a_value == b_value:
		return a.alias < b.alias
	return a_value > b_value


func _refresh() -> void:
	_refresh_id += 1
	var my_id := _refresh_id
	var by_id: Dictionary = {}
	var failed := false
	# Four boards, four requests: Talo has no combined endpoint and GDScript can't join
	# concurrent awaits, so they land in sequence. Only ever on open — sorting is local.
	for sort in [
		BoardEntry.Sort.KILLS,
		BoardEntry.Sort.DEATHS,
		BoardEntry.Sort.RATIO,
		BoardEntry.Sort.RECENT,
	]:
		var page: LeaderboardsAPI.EntriesPage = await GlobalLeaderboard.entries(0, _board_of(sort))
		if my_id != _refresh_id or not visible:
			return
		if page == null:
			failed = true
			continue
		for entry in page.entries:
			_absorb(by_id, sort, entry)
	# A wordless table has no room to explain itself, so a dead request reddens the emblem.
	_emblem.modulate = Palette.RED if failed else Color.WHITE
	var entries: Array[BoardEntry] = []
	entries.assign(by_id.values())
	show_entries(entries)


func _board_of(sort: BoardEntry.Sort) -> String:
	match sort:
		BoardEntry.Sort.KILLS:
			return GlobalLeaderboard.LB_UNIQUE_KILLS
		BoardEntry.Sort.DEATHS:
			return GlobalLeaderboard.LB_DEATHS
		BoardEntry.Sort.RATIO:
			return GlobalLeaderboard.LB_DAMAGE_RATIO
		_:
			return GlobalLeaderboard.LB_DEATH_FEED


# Fold one board entry into its player's row, creating the row the first time that player is
# seen on any board. The feed is non-unique (one entry per death, newest first), so only a
# player's FIRST appearance there counts — that one is their latest death.
func _absorb(by_id: Dictionary, sort: BoardEntry.Sort, entry: TaloLeaderboardEntry) -> void:
	var alias := entry.player_alias
	if alias == null or alias.player == null:
		return
	var row: BoardEntry = by_id.get(alias.player.id)
	if row == null:
		row = BoardEntry.new()
		row.player_id = alias.player.id
		row.alias = alias.display_name
		by_id[alias.player.id] = row
	match sort:
		BoardEntry.Sort.KILLS:
			# Whole part = distinct enemy types; the fraction is only a total-kills tiebreak.
			row.kills = floorf(entry.score)
			row.bestiary = GlobalLeaderboard.parse_kills(entry.get_prop("bestiary", "{}"))
		BoardEntry.Sort.DEATHS:
			row.deaths = entry.score
		BoardEntry.Sort.RATIO:
			row.ratio = entry.score
		BoardEntry.Sort.RECENT:
			if row.last_death == BoardEntry.MISSING:
				row.last_death = entry.score
				row.killer = entry.get_prop("killer", "")
