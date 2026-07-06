extends Control

## Page indicator as pixel dots (filled = current page) — the no-text stand-in for a
## "page 3/5" label.

const _DOT := 2
const _GAP := 2
const _ON := Color("dff6f5")
# Bag-slot gray, not the palette dark — the dark vanishes against the panel background.
const _OFF := Color("7d7071")

var pages: int = 1:
	set(value):
		pages = maxi(1, value)
		update_minimum_size()
		queue_redraw()

var current: int = 0:
	set(value):
		current = value
		queue_redraw()

func _get_minimum_size() -> Vector2:
	return Vector2(pages * (_DOT + _GAP) - _GAP, _DOT)

func _draw() -> void:
	for i in pages:
		draw_rect(Rect2(i * (_DOT + _GAP), 0, _DOT, _DOT), _ON if i == current else _OFF)
