extends PanelContainer

## Online kills top-list, refreshed each time the panel opens. Rows are rank,
## name, score; the player's own row is tinted. When the player sits below the
## visible top, the last row becomes their real-ranked entry instead.

const MAX_ROWS := 12
const COLOR_SELF := Palette.APRICOT

@onready var _rows: VBoxContainer = %Rows

# Distinguishes overlapping refreshes: a fetch resolving after the panel was
# closed and reopened must not append onto the newer fetch's rows.
var _refresh_id := 0


func _ready() -> void:
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		accept_event()
		hide()


func _refresh() -> void:
	_refresh_id += 1
	var my_id := _refresh_id
	for c in _rows.get_children():
		c.queue_free()
	var page: LeaderboardsAPI.EntriesPage = await GlobalLeaderboard.entries(0)
	if my_id != _refresh_id or not visible or page == null:
		return
	var own_alias: int = Talo.current_alias.id if Talo.current_alias else -1
	var shown := page.entries.slice(0, MAX_ROWS)
	var own_shown: bool = shown.any(func(e: TaloLeaderboardEntry) -> bool:
		return e.player_alias.id == own_alias)
	if not own_shown:
		var mine: TaloLeaderboardEntry = await GlobalLeaderboard.my_entry()
		if my_id != _refresh_id or not visible:
			return
		if mine != null:
			if shown.size() == MAX_ROWS:
				shown.resize(MAX_ROWS - 1)
			shown.append(mine)
	for entry in shown:
		_rows.add_child(_make_row(entry, entry.player_alias.id == own_alias))


func _make_row(entry: TaloLeaderboardEntry, own: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var rank := Label.new()
	rank.custom_minimum_size = Vector2(18, 0)
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rank.text = str(entry.position + 1)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text = entry.player_alias.display_name
	var score := Label.new()
	score.custom_minimum_size = Vector2(30, 0)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.text = str(int(entry.score))
	for label in [rank, name_label, score]:
		if own:
			label.add_theme_color_override("font_color", COLOR_SELF)
		row.add_child(label)
	return row
