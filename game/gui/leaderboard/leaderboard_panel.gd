extends PanelContainer

## Placeholder text-only boards panel while the backend settles: one tab per
## board, every row a plain text line, and a text bestiary card when a row is
## clicked. The proper icon UI returns once the data proves out.

const MAX_ROWS := 10

@onready var _main: VBoxContainer = %Main
@onready var _rows: VBoxContainer = %Rows
@onready var _card: PanelContainer = %Card
@onready var _card_text: Label = %CardText
@onready var _tabs: Array[Button] = [%KillsTab, %DeathsTab, %RatioTab, %FeedTab]
# Tab index -> board internal name; index 3 (feed) renders its own line shape.
@onready var _boards: Array[String] = [
	GlobalLeaderboard.LB_UNIQUE_KILLS,
	GlobalLeaderboard.LB_DEATHS,
	GlobalLeaderboard.LB_DAMAGE_RATIO,
	GlobalLeaderboard.LB_DEATH_FEED,
]

# Distinguishes overlapping refreshes: a fetch resolving after the panel was
# closed and reopened must not append onto the newer fetch's rows.
var _refresh_id := 0
var _tab := 0


func _ready() -> void:
	visibility_changed.connect(func() -> void:
		if visible:
			_close_card()
			_refresh())
	for i in _tabs.size():
		_tabs[i].pressed.connect(_on_tab.bind(i))
	_card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close_card())


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		accept_event()
		if _card.visible:
			_close_card()
		else:
			hide()


func _on_tab(i: int) -> void:
	_tab = i
	_close_card()
	_refresh()


func _refresh() -> void:
	_refresh_id += 1
	var my_id := _refresh_id
	for i in _tabs.size():
		_tabs[i].set_pressed_no_signal(i == _tab)
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var page: LeaderboardsAPI.EntriesPage = await GlobalLeaderboard.entries(0, _boards[_tab])
	if my_id != _refresh_id or not visible:
		return
	if page == null:
		_rows.add_child(_make_line("(fetch failed)", null))
		return
	if page.entries.is_empty():
		_rows.add_child(_make_line("(no entries)", null))
		return
	for entry in page.entries.slice(0, MAX_ROWS):
		_rows.add_child(_make_line(_line_text(entry), entry))


func _line_text(entry: TaloLeaderboardEntry) -> String:
	var alias := entry.player_alias.display_name
	if _tab == 3:
		return "%s  by:%s  [%s]" % [
			alias,
			entry.get_prop("killer", "?"),
			entry.get_prop("loadout", ""),
		]
	var score := "%.1f" % entry.score if _tab == 2 else str(int(entry.score))
	return "%d. %s  %s" % [entry.position + 1, alias, score]


func _make_line(text: String, entry: TaloLeaderboardEntry) -> Control:
	var label := Label.new()
	label.text = text
	label.clip_text = true
	if entry != null and entry.player_alias.player != null:
		var player_id: String = entry.player_alias.player.id
		var display_name: String = entry.player_alias.display_name
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				_open_card(player_id, display_name))
	return label


func _open_card(player_id: String, display_name: String) -> void:
	_main.visible = false
	_card.visible = true
	_card_text.text = "%s\n..." % display_name
	var my_id := _refresh_id  # card belongs to this open; a stale fetch must not fill it
	var bestiary := await GlobalLeaderboard.bestiary_of(player_id)
	var deaths_entry := await GlobalLeaderboard.player_entry(player_id, GlobalLeaderboard.LB_DEATHS)
	if my_id != _refresh_id or not _card.visible:
		return
	var lines := PackedStringArray()
	lines.append(display_name)
	lines.append("deaths: %d" % int(deaths_entry.score) if deaths_entry != null else "deaths: ?")
	var total := 0
	for id in GlobalBestiary.roster():
		var kills := int(bestiary.get(String(id), 0))
		total += kills
		lines.append("%s: %d" % [id, kills] if kills > 0 else "%s: -" % id)
	lines.append("unique %d/%d, total %d" % [bestiary.size(), GlobalBestiary.roster().size(), total])
	_card_text.text = "\n".join(lines)


func _close_card() -> void:
	_refresh_id += 1  # invalidate in-flight card fetches
	_card.visible = false
	_main.visible = true
