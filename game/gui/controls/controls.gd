extends PanelContainer

## The controls recap: every binding the game ships, keyboard prompt on the left, pad prompt
## beside it, what it does on the right. One page per group of bindings — play, HUD, bag, map
## — turned like the bestiary's, dpad left/right on a pad, the arrows on the strip, or the
## buttons. Lives on the live game (no pausing), toggled from the keyboard button on the HUD
## strip; Esc or the close button dismisses it.
##
## The bindings themselves live in controls.tscn: %RowsArea holds one VBoxContainer per page
## and this script shows one of them at a time. A page's node name is the title it shows, and
## it holds two three-column GridContainers — the column titles, then the bindings, as
## keyboard prompts, pad prompts, description — both full width, so both divide into the same
## centred thirds.
##
## What the page lists is a reading of `design/docs/input.md`, not a second source of truth:
## the project file's `[input]` section is what actually binds. When a binding changes, the
## scene and that doc want the same edit — test_controls_page.gd checks that the prompts
## resolve and the rows fit, not that the bindings are current, which only a human notices.

var _page := 0

@onready var _pages: Array[Node] = %RowsArea.get_children()

func _ready() -> void:
	%PrevPage.pressed.connect(func() -> void: _set_page(_page - 1))
	%NextPage.pressed.connect(func() -> void: _set_page(_page + 1))
	%CloseButton.pressed.connect(hide)
	%PageDots.pages = _pages.size()
	_set_page(0)

## Pad paging, the only interaction the page has — same gate as the bestiary's: only a
## pad-opened page reads the dpad, since the keyboard's arrows share ui_left/ui_right and
## belong to whatever else has them. The left stick never reaches here (movement only), so
## the mage keeps walking while the page is up.
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

func _set_page(page: int) -> void:
	_page = clampi(page, 0, _pages.size() - 1)
	for i in _pages.size():
		(_pages[i] as Control).visible = i == _page
	%PageTitle.text = String(_pages[_page].name)
	# Arrows dim at the ends instead of hiding, so the nav row never shifts.
	_set_arrow(%PrevPage, _page > 0)
	_set_arrow(%NextPage, _page < _pages.size() - 1)
	%PageDots.current = _page

func _set_arrow(arrow: TextureButton, enabled: bool) -> void:
	arrow.disabled = not enabled
	arrow.self_modulate.a = 1.0 if enabled else 0.4
