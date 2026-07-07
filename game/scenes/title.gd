extends Control

## The startup screen. Two options: New (roll a fresh world and start in the glade with
## starter gear) and Continue (resume the saved seed). Both open the streamed world;
## Continue is disabled until a save exists.

@export var new_game_scene: PackedScene
@export var continue_scene: PackedScene

const _THEME = preload("res://gui/theme.tres")

@onready var _new_btn: Button = %NewButton
@onready var _continue_btn: Button = %ContinueButton
@onready var _bg: ColorRect = $Bg
@onready var _title_label: Label = $TitleLabel

# Idle/selected are brightness steps of the theme mint; disabled gets its own hue
# (Zughy 32 grey) so "unavailable" reads at a glance instead of just dimmer text.
const COLOR_SELECTED := Palette.WHITE
static var COLOR_IDLE: Color = Palette.WHITE.darkened(0.45)
const COLOR_DISABLED := Palette.GREY
const COLOR_BG := Palette.BLACK
const COLOR_TITLE := Palette.APRICOT

var _owned_icons: Array[Texture2D] = []
var _icon_popup: PanelContainer = null


func _ready() -> void:
	_bg.color = COLOR_BG
	_title_label.add_theme_color_override("font_color", COLOR_TITLE)

	for btn in [_new_btn, _continue_btn]:
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(state, empty)
		btn.add_theme_color_override("font_color", COLOR_IDLE)
		btn.add_theme_color_override("font_hover_color", COLOR_SELECTED)
		btn.add_theme_color_override("font_focus_color", COLOR_SELECTED)
		btn.add_theme_color_override("font_pressed_color", COLOR_SELECTED)
		btn.add_theme_color_override("font_disabled_color", COLOR_DISABLED)
		btn.mouse_entered.connect(func() -> void:
			if not btn.disabled:
				btn.grab_focus())

	_new_btn.pressed.connect(_on_new)
	_continue_btn.pressed.connect(_on_continue)

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
	var keys := ["weapon", "hat", "robe"]
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
	_icon_popup.theme = _THEME
	var frame: StyleBox = _THEME.get_stylebox("panel", "PanelContainer").duplicate()
	frame.set_content_margin_all(1)
	_icon_popup.add_theme_stylebox_override("panel", frame)
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


func _on_new() -> void:
	GameState.new_game()
	SceneManager.go_to(new_game_scene)


func _on_continue() -> void:
	if GameState.continue_game():
		SceneManager.go_to(continue_scene)
