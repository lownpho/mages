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
	# Godot's default icons are 16px beside an 8px font. A CheckBox reserves room for its largest
	# icon, radio ones included.
	for state in ["", "_disabled"]:
		for kind in ["", "radio_"]:
			t.set_icon(kind + "unchecked" + state, "CheckBox", _box_icon(dark, edge))
			t.set_icon(kind + "checked" + state, "CheckBox", _box_icon(Color(0.6, 0.72, 0.88), edge))
	t.set_constant("h_separation", "CheckBox", 2)
	var arrow := Color(0.75, 0.8, 0.88)
	var up := PackedStringArray(["..#..", ".###.", "#####"])
	var down := PackedStringArray(["#####", ".###.", "..#.."])
	t.set_icon("arrow", "OptionButton", _pattern_icon(down, arrow))
	t.set_icon("updown", "SpinBox", _pattern_icon(up + PackedStringArray(["....."]) + down, arrow))
	for state in ["", "_hover", "_pressed", "_disabled"]:
		t.set_icon("up" + state, "SpinBox", _pattern_icon(up, arrow))
		t.set_icon("down" + state, "SpinBox", _pattern_icon(down, arrow))

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


## A 7px check box: a 1px border around a dark well holding a 3px square of the given colour.
static func _box_icon(mark: Color, border: Color) -> ImageTexture:
	var image := Image.create_empty(7, 7, false, Image.FORMAT_RGBA8)
	image.fill(border)
	image.fill_rect(Rect2i(1, 1, 5, 5), Color(0.10, 0.11, 0.14))
	image.fill_rect(Rect2i(2, 2, 3, 3), mark)
	return ImageTexture.create_from_image(image)


## A small icon drawn from rows of text: "#" is a pixel of the colour, anything else transparent.
static func _pattern_icon(rows: PackedStringArray, color: Color) -> ImageTexture:
	var image := Image.create_empty(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "#":
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


static func _sb_pad(px: int) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = px
	s.content_margin_right = px
	s.content_margin_top = px
	s.content_margin_bottom = px
	return s
