extends PanelContainer

## Login/register form for the optional leaderboard account. Same form serves both:
## LOGIN tries the credentials, REGISTER claims them. Errors surface as one terse
## word — the server owns the rules (uniqueness, profanity), we just relay them.
## Success needs no handling here: the session lands via GlobalEvent's
## leaderboard_session_changed, which also tells the title screen to update.

const COLOR_ERROR := Palette.RED

@onready var _name_edit: LineEdit = %NameEdit
@onready var _password_edit: LineEdit = %PasswordEdit
@onready var _login_btn: Button = %LoginButton
@onready var _register_btn: Button = %RegisterButton
@onready var _error_label: Label = %ErrorLabel

var _busy := false


func _ready() -> void:
	_error_label.add_theme_color_override("font_color", COLOR_ERROR)
	_login_btn.pressed.connect(_submit.bind(false))
	_register_btn.pressed.connect(_submit.bind(true))
	# Enter from either field = login, the common case; registering is a deliberate click.
	_name_edit.text_submitted.connect(func(_t: String) -> void: _submit(false))
	_password_edit.text_submitted.connect(func(_t: String) -> void: _submit(false))
	GlobalEvent.leaderboard_session_changed.connect(func(logged_in: bool) -> void:
		if logged_in:
			hide())


func open() -> void:
	_error_label.text = ""
	_password_edit.clear()
	show()
	_name_edit.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		accept_event()
		hide()


func _submit(register: bool) -> void:
	if _busy:
		return
	var account_name := _name_edit.text.strip_edges()
	if account_name.is_empty() or _password_edit.text.is_empty():
		_error_label.text = "MISSING"
		return
	_set_busy(true)
	var err: TaloPlayerAuthError
	if register:
		err = await GlobalLeaderboard.register(account_name, _password_edit.text)
	else:
		err = await GlobalLeaderboard.login(account_name, _password_edit.text)
	_set_busy(false)
	if err != null:
		_error_label.text = _word_for(err.code)
	# else: hidden by the session-changed handler.


func _set_busy(busy: bool) -> void:
	_busy = busy
	_login_btn.disabled = busy
	_register_btn.disabled = busy


func _word_for(code: TaloPlayerAuthError.ErrorCode) -> String:
	match code:
		TaloPlayerAuthError.ErrorCode.INVALID_CREDENTIALS:
			return "WRONG"
		TaloPlayerAuthError.ErrorCode.IDENTIFIER_TAKEN:
			return "TAKEN"
		TaloPlayerAuthError.ErrorCode.IDENTIFIER_PROFANITY:
			return "RUDE"
		TaloPlayerAuthError.ErrorCode.API_ERROR:
			return "OFFLINE"
		_:
			return "ERROR"
