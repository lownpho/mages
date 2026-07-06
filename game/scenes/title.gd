extends Control

## The startup screen. Two options: New (roll a fresh world and start from the tutorial)
## and Continue (resume the saved seed straight into the streamed world). Continue is
## disabled until a save exists.

@export var new_game_scene: PackedScene
@export var continue_scene: PackedScene

@onready var _new_btn: Button = %NewButton
@onready var _continue_btn: Button = %ContinueButton

# Only the theme's Label mint exists as a UI colour; selection and the disabled state
# are opaque brightness steps of it (no invented hues, no transparency).
const COLOR_SELECTED := Color(0.8745098, 0.9647059, 0.9607843)  # theme mint, full
const COLOR_IDLE := Color(0.481, 0.531, 0.528)                  # mint dimmed
const COLOR_DISABLED := Color(0.262, 0.29, 0.288)               # mint dimmer


func _ready() -> void:
	for btn in [_new_btn, _continue_btn]:
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "focus"]:
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
	# Land the cursor on the most likely choice: Continue if there's a save, else New.
	(_new_btn if _continue_btn.disabled else _continue_btn).grab_focus()


func _on_new() -> void:
	GameState.new_game()
	SceneManager.go_to(new_game_scene)


func _on_continue() -> void:
	if GameState.continue_game():
		SceneManager.go_to(continue_scene)
