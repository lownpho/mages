extends Control

## The startup screen. Two options: New (roll a fresh world and start in the glade with
## starter gear) and Continue (resume the saved seed). Both open the streamed world;
## Continue is disabled until a save exists.

@export var new_game_scene: PackedScene
@export var continue_scene: PackedScene

@onready var _new_btn: Button = %NewButton
@onready var _continue_btn: Button = %ContinueButton
@onready var _account_btn: Button = %AccountButton
@onready var _board_btn: Button = %LeaderboardButton
@onready var _auth_dialog: PanelContainer = %AuthDialog
@onready var _board: PanelContainer = %LeaderboardPanel
@onready var _menu: VBoxContainer = $Menu
@onready var _meta_row: HBoxContainer = $MetaRow
@onready var _bg: ColorRect = $Bg
@onready var _title_label: Label = $TitleLabel

const COLOR_BG := Palette.BLACK
const COLOR_TITLE := Palette.APRICOT

var _owned_icons: Array[Texture2D] = []
var _icon_popup: PanelContainer = null


func _ready() -> void:
	_bg.color = COLOR_BG
	_title_label.add_theme_color_override("font_color", COLOR_TITLE)

	# Button idle/selected/disabled looks come from the project theme; hover just
	# moves the keyboard/pad focus so the two selection cues can never disagree.
	for btn in [_new_btn, _continue_btn, _board_btn, _account_btn]:
		btn.mouse_entered.connect(func() -> void:
			if not btn.disabled:
				btn.grab_focus())

	_new_btn.pressed.connect(_on_new)
	_continue_btn.pressed.connect(_on_continue)

	# The meta row (bottom corner, apart from the run menu) is the online side:
	# LEADERBOARD (only offered with an account) and the account button, which
	# doubles as the status readout — LOGIN when logged out, the account name when
	# logged in (pressing it then logs out). Either overlay swallows both button
	# groups while open so hover can't steal focus from it.
	_account_btn.pressed.connect(_on_account)
	_board_btn.pressed.connect(func() -> void: _board.visible = not _board.visible)
	for overlay in [_auth_dialog, _board]:
		overlay.visibility_changed.connect(func() -> void:
			var overlay_open: bool = _auth_dialog.visible or _board.visible
			_menu.visible = not overlay_open
			_meta_row.visible = not overlay_open)
	GlobalEvent.leaderboard_session_changed.connect(func(_logged_in: bool) -> void: _refresh_account())
	_refresh_account()

	_continue_btn.disabled = not GameState.has_save()
	_owned_icons = _gather_owned_icons()
	_continue_btn.mouse_entered.connect(_show_icon_popup)
	_continue_btn.mouse_exited.connect(_hide_icon_popup)
	# Land the cursor on the most likely choice: Continue if there's a save, else New.
	(_new_btn if _continue_btn.disabled else _continue_btn).grab_focus()


## Peeks the save file for the icons of every item the saved run owns (equipped +
## bagged + slotted spells), without touching the live GlobalInventory — Continue
## hasn't been pressed yet, so nothing should actually load until it is.
func _gather_owned_icons() -> Array[Texture2D]:
	var icons: Array[Texture2D] = []
	if not GameState.has_save():
		return icons
	var cfg := ConfigFile.new()
	if cfg.load(GameState.SAVE_PATH) != OK:
		return icons
	var keys := []
	for i in range(GlobalInventory.BAG_SIZE):
		keys.append("bag_%d" % i)
	for i in range(GlobalInventory.SPELL_SLOT_SIZE):
		keys.append("spell_%d" % i)
	for key in keys:
		var path: String = cfg.get_value("inventory", key, "")
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var item: ItemResource = load(path)
		if item and item.icon:
			icons.append(item.icon)
	return icons


# Shown/hidden directly off mouse_entered/exited rather than the built-in tooltip
# system, whose fixed delay makes the icons feel laggy on a menu this small.
func _show_icon_popup() -> void:
	if _owned_icons.is_empty() or _icon_popup:
		return
	_icon_popup = PanelContainer.new()
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	for icon in _owned_icons:
		var rect := TextureRect.new()
		rect.texture = icon
		rect.custom_minimum_size = Vector2(8, 8)
		grid.add_child(rect)
	_icon_popup.add_child(grid)
	_icon_popup.top_level = true
	add_child(_icon_popup)
	var popup_size := _icon_popup.get_combined_minimum_size()
	_icon_popup.global_position = _title_label.global_position + Vector2(
		(_title_label.size.x - popup_size.x) / 2.0, _title_label.size.y + 4)


func _hide_icon_popup() -> void:
	if _icon_popup:
		_icon_popup.queue_free()
		_icon_popup = null


func _refresh_account() -> void:
	_account_btn.text = GlobalLeaderboard.username().to_upper() if GlobalLeaderboard.logged_in else "LOGIN"
	_board_btn.visible = GlobalLeaderboard.logged_in
	if not GlobalLeaderboard.logged_in:
		_board.hide()


func _on_account() -> void:
	if GlobalLeaderboard.logged_in:
		GlobalLeaderboard.logout()
	else:
		_auth_dialog.open()


func _on_new() -> void:
	GameState.new_game()
	SceneManager.go_to(new_game_scene)


func _on_continue() -> void:
	if GameState.continue_game():
		SceneManager.go_to(continue_scene)
