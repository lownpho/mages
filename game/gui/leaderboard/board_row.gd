class_name BoardRow
extends Button

## One rendered leaderboard line: rank, alias, the three metric columns, and the icon of
## whatever killed this player last. Columns the player isn't on show a dash. The whole line is
## one Button, so hover, keyboard focus (the theme's IconButton ring) and the click that opens
## their bestiary all come for free.

const MISSING_TEXT := "-"
## The killer icon dims with the rest of the line rather than going grey — it's already a
## full-colour sprite, and a silhouette would read as "undiscovered" like a bestiary cell.
const DIM_ICON_ALPHA := 0.7
## Rank is the least interesting thing on the line and the alias the most, so they sit at two
## different neutrals; the metrics wear their column's hue (BoardEntry.COLORS).
const RANK_COLOR := Palette.GREY
const ALIAS_COLOR := Palette.SILVER
const LIT_ALIAS_COLOR := Palette.WHITE

var entry: BoardEntry

var _is_me := false


func _ready() -> void:
	# Hover moves the focus rather than painting its own highlight, so the mouse and the
	# keyboard can never disagree about which line is selected (same rule as the title menu).
	mouse_entered.connect(func() -> void: grab_focus())
	focus_entered.connect(_apply_tint)
	focus_exited.connect(_apply_tint)


## `roster_size` is how many enemies are filed in the bestiary at all, so the kills column reads
## as completion ("19/35") rather than a bare count. It is handed in because it is the same for
## every line and derived once per fill, not per row.
func bind(p_entry: BoardEntry, rank: int, is_me: bool, roster_size: int) -> void:
	entry = p_entry
	_is_me = is_me
	%Rank.text = str(rank)
	%Alias.text = p_entry.alias
	%Kills.text = _fraction(p_entry.kills, roster_size)
	%Deaths.text = _number(p_entry.deaths, false)
	%Ratio.text = _number(p_entry.ratio, true)
	_bind_killer(StringName(p_entry.killer))
	_apply_tint()


# Only a real roster id resolves to a sheet; an unattributed death (a blast has no source
# enemy) or a stale id leaves the cell blank rather than crashing on a missing resource.
func _bind_killer(killer: StringName) -> void:
	var known: bool = killer != &"" and killer in GlobalBestiary.roster()
	# ponytail: the cell is one tile, so the four 16x16 icons halve cleanly but gnarlking
	# (16x24) and stalker (8x16) land on a fractional scale and go soft. Widen the column to
	# two tiles if that ever matters.
	%Killer.texture = GlobalBestiary.load_data(killer).icon if known else null


# Your own line, and whichever line is hovered or focused, steps forward — so you can find
# yourself without a marker column. The metric colours are deliberately NOT part of that: they
# are the only thing identifying which column a number belongs to, so dimming them by row would
# trade away the readability they exist for. The highlight rides on the two neutrals instead.
func _apply_tint() -> void:
	var lit := _is_me or has_focus()
	%Rank.add_theme_color_override(&"font_color", ALIAS_COLOR if lit else RANK_COLOR)
	%Alias.add_theme_color_override(&"font_color", LIT_ALIAS_COLOR if lit else ALIAS_COLOR)
	var metrics: Array[Label] = [%Kills, %Deaths, %Ratio]
	for i in metrics.size():
		metrics[i].add_theme_color_override(&"font_color", BoardEntry.COLORS[i])
	%Killer.modulate.a = 1.0 if lit else DIM_ICON_ALPHA


# Distinct types killed out of the whole filed roster — the same fraction the bestiary shows in
# its own corner, so a line here and that player's book agree on the number.
func _fraction(value: float, total: int) -> String:
	if value == BoardEntry.MISSING:
		return MISSING_TEXT
	return "%d/%d" % [int(value), total]


func _number(value: float, decimal: bool) -> String:
	if value == BoardEntry.MISSING:
		return MISSING_TEXT
	return "%.1f" % value if decimal else str(int(value))
