extends CanvasLayer

# Spell-row frames: the active page's row wears the spell-slot frame, the
# inactive row the bag-slot frame — the palette-safe "which page is live" cue.
const _ACTIVE_FRAME := preload("res://gui/spellslot_atlas.tres")
const _INACTIVE_FRAME := preload("res://gui/spellslot_inactive_atlas.tres")

const UiSlot = preload("res://gui/ui_slot.gd")

func _ready() -> void:
	GlobalEvent.player_max_health_changed.connect(_on_player_max_health_changed)
	GlobalEvent.player_health_changed.connect(_on_player_health_changed)
	GlobalEvent.player_skill_changed.connect(_on_player_skill_changed)
	GlobalEvent.player_speed_changed.connect(_on_player_speed_changed)
	GlobalEvent.player_defence_changed.connect(_on_player_defence_changed)
	GlobalEvent.spell_page_changed.connect(_on_spell_page_changed)

	# Assign the ui_slots to the ui_slots
	var ui_slots = %Bag.get_children()
	for i in range(GlobalInventory.BAG_SIZE):
		ui_slots[i].slot = GlobalInventory.bag_slots.at(i)
	# Both spell pages are visible as two rows of two (LMB/RMB left to right);
	# SPACE / the mouse wheel swap which row is live, shown by the frame swap.
	ui_slots = %EquipSpells.get_children()
	for i in range(GlobalInventory.SPELL_SLOT_SIZE):
		ui_slots[i].slot = GlobalInventory.spell_slots.at(i)
	_on_spell_page_changed(GlobalInventory.active_spell_page)

	# Show the value overlay only while hovering the bar.
	_setup_bar_hover(%HealthBar, %HealthValue)

	# The bestiary and the map are the two HUD-strip overlays; opening one closes the other so
	# only ever one is up (Esc / an outside click closes whichever is open — see _unhandled_input).
	%BestiaryButton.pressed.connect(_toggle_panel.bind(%BestiaryPanel))
	%MapButton.pressed.connect(_toggle_panel.bind(%MapPanel))

	# There's no pause menu by design and no process to "quit" on the web build, so this
	# leaves the run to the title screen. The run autosaves continuously; persist() first
	# flushes the player's current position (only snapshotted every few seconds) so
	# Continue resumes exactly here.
	%QuitButton.pressed.connect(func() -> void:
		GameState.persist()
		SceneManager.go_to(load("res://scenes/title.tscn")))

	# Clicking a strip button grabs focus, leaving its ring stuck under the
	# cursor — only pad navigation should keep focus visible.
	for btn in [%BestiaryButton, %MapButton, %QuitButton]:
		btn.pressed.connect(func() -> void:
			if not GlobalInput.using_gamepad:
				btn.release_focus())

func _toggle_panel(panel: Control) -> void:
	var opening: bool = not panel.visible
	for p in [%BestiaryPanel, %MapPanel]:
		p.visible = p == panel and opening


func _on_spell_page_changed(page: int) -> void:
	var ui_slots = %EquipSpells.get_children()
	for i in range(GlobalInventory.SPELL_SLOT_SIZE):
		@warning_ignore("integer_division")
		var row := i / GlobalInventory.SPELL_PAGE_SIZE
		ui_slots[i].slot_texture = _ACTIVE_FRAME if row == page else _INACTIVE_FRAME

func _unhandled_input(event: InputEvent) -> void:
	# Reaching _unhandled_input at all means the click missed every Control (an open
	# panel included, since its mouse_filter stops input) — so any mouse press here is,
	# by construction, a click outside the UI. (The map consumes its own clicks for
	# pins/pan, so only clicks that miss it land here.) Wheel notches don't count as clicks,
	# so scrolling — over the map or the strip — never closes an open panel.
	var outside_click: bool = event is InputEventMouseButton and event.pressed \
			and event.button_index != MOUSE_BUTTON_WHEEL_UP \
			and event.button_index != MOUSE_BUTTON_WHEEL_DOWN
	if outside_click:
		# A ground click while click-carrying an item would otherwise cast with the
		# carry still silently armed — the click cancels it instead.
		UiSlot.cancel_carry()
	# Web's Fullscreen API reserves Esc to exit fullscreen and can't be
	# preventDefault()'d, so sharing it with a UI action there is a losing fight —
	# on web only the keyboard Esc is skipped; the pad's Start button still works.
	var menu_pressed: bool = event.is_action_pressed("menu") \
			and not (OS.get_name() == "Web" and event is InputEventKey)
	# Pad B backs out of an open panel; only the joypad binding, so web Esc
	# (which shares ui_cancel) keeps its hands off.
	var pad_back: bool = event.is_action_pressed("ui_cancel") and event is InputEventJoypadButton
	if %BestiaryPanel.visible or %MapPanel.visible:
		if outside_click or menu_pressed or pad_back:
			%BestiaryPanel.hide()
			%MapPanel.hide()
			get_viewport().set_input_as_handled()
	elif menu_pressed:
		_toggle_slot_nav()
		get_viewport().set_input_as_handled()
	elif GlobalInput.ui_captured and event.is_action_pressed("ui_cancel"):
		# B/Esc with no panel open and nothing carried (a slot consumes it while
		# carrying): leave slot navigation.
		_exit_slot_nav()
		get_viewport().set_input_as_handled()

# Controller inventory access: Start enters "slot navigation" — focus lands on the
# first spell slot and GlobalInput.ui_captured stands gameplay input down so the
# stick moves the focus, not the mage. Mouse/keyboard never needs the mode (slots
# are clickable directly), so only a pad enters it; exiting is always allowed.
func _toggle_slot_nav() -> void:
	if GlobalInput.ui_captured:
		_exit_slot_nav()
	elif GlobalInput.using_gamepad:
		%EquipSpells.get_child(0).grab_focus()
		GlobalInput.set_ui_captured(true)

func _exit_slot_nav() -> void:
	UiSlot.cancel_carry()
	get_viewport().gui_release_focus()
	GlobalInput.set_ui_captured(false)

func _setup_bar_hover(bar: ProgressBar, label: Label) -> void:
	# self_modulate hides the bar's own fill/bg drawing without affecting the child label.
	bar.mouse_entered.connect(func() -> void:
		bar.self_modulate.a = 0.0
		label.visible = true)
	bar.mouse_exited.connect(func() -> void:
		bar.self_modulate.a = 1.0
		label.visible = false)

func _on_player_max_health_changed(max_health: int) -> void:
	%HealthBar.max_value = max_health
	_refresh_bar_value(%HealthBar, %HealthValue)

func _on_player_health_changed(health: int) -> void:
	%HealthBar.value = health
	_refresh_bar_value(%HealthBar, %HealthValue)

func _refresh_bar_value(bar: ProgressBar, label: Label) -> void:
	label.text = "%d/%d" % [bar.value, bar.max_value]

func _on_player_skill_changed(skill: int) -> void:
	%SkillValue.text = str(skill)

func _on_player_speed_changed(speed: int) -> void:
	%SpeedValue.text = str(speed)

func _on_player_defence_changed(defence: int) -> void:
	%DefenceValue.text = str(defence)
