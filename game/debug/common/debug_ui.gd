class_name DebugUi
## Shared chrome for the debug tools. The game theme.tres styles only Label/PanelContainer;
## Button/OptionButton/CheckBox/SpinBox/TabContainer fall back to Godot's default styleboxes,
## which are sized for a 16px UI and dwarf the 8px pixel font. Duplicate the game theme and
## pin tight, HUD-consistent chrome onto those types.
extends RefCounted

static var _theme: Theme = null


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t: Theme = (load("res://gui/theme.tres") as Theme).duplicate(true)
	var base := Color(0.16, 0.18, 0.22)
	var lit := Color(0.24, 0.28, 0.35)
	var dark := Color(0.10, 0.11, 0.14)
	var edge := Color(0.38, 0.44, 0.53)

	for type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			t.set_stylebox(state, type, _sb(dark if state == "pressed" else \
					(lit if state == "hover" else base), edge))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())

	t.set_stylebox("normal", "LineEdit", _sb(dark, edge))
	t.set_stylebox("focus", "LineEdit", _sb(dark, Color(0.6, 0.72, 0.88)))
	t.set_constant("minimum_character_width", "LineEdit", 3)

	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CheckBox", _sb_pad(2))
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())

	t.set_stylebox("tab_selected", "TabContainer", _sb(lit, edge))
	t.set_stylebox("tab_unselected", "TabContainer", _sb(dark, edge))
	t.set_stylebox("tab_hovered", "TabContainer", _sb(base, edge))
	t.set_stylebox("panel", "TabContainer", _sb_pad(2))
	t.set_constant("icon_max_width", "TabContainer", 0)
	_theme = t
	return t


## Compact filled box: 1px border, wide-but-short content margins for dense controls.
static func _sb(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.content_margin_left = 3
	s.content_margin_right = 3
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	return s


static func _sb_pad(px: int) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = px
	s.content_margin_right = px
	s.content_margin_top = px
	s.content_margin_bottom = px
	return s
