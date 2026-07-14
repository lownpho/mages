extends CanvasLayer

# Spell-row frames: the active page's row wears the spell-slot frame, the
# inactive row the bag-slot frame — the palette-safe "which page is live" cue.
const _ACTIVE_FRAME := preload("res://gui/spellslot_atlas.tres")
const _INACTIVE_FRAME := preload("res://gui/bagslot_atlas.tres")

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
	# Both spell pages are visible as two rows of three (LMB/RMB/Space left to
	# right); SHIFT swaps which row is live, shown by the frame swap.
	ui_slots = %EquipSpells.get_children()
	for i in range(GlobalInventory.SPELL_SLOT_SIZE):
		ui_slots[i].slot = GlobalInventory.spell_slots.at(i)
	_on_spell_page_changed(GlobalInventory.active_spell_page)

	# Show the value overlay only while hovering the bar.
	_setup_bar_hover(%HealthBar, %HealthValue)

	# The bestiary and the map are the two HUD-strip overlays; opening one closes the other so
	# only ever one is up (Esc / an outside click closes whichever is open — see _unhandled_input).
	%BestiaryButton.pressed.connect(func() -> void:
		%BestiaryPanel.visible = not %BestiaryPanel.visible
		if %BestiaryPanel.visible:
			%MapPanel.hide())
	%MapButton.pressed.connect(func() -> void:
		%MapPanel.visible = not %MapPanel.visible
		if %MapPanel.visible:
			%BestiaryPanel.hide())

	# There's no pause menu by design and no process to "quit" on the web build, so this
	# leaves the run to the title screen. The run autosaves continuously; persist() first
	# flushes the player's current position (only snapshotted every few seconds) so
	# Continue resumes exactly here.
	%QuitButton.pressed.connect(func() -> void:
		GameState.persist()
		SceneManager.go_to(load("res://scenes/title.tscn")))

func _on_spell_page_changed(page: int) -> void:
	var ui_slots = %EquipSpells.get_children()
	for i in range(GlobalInventory.SPELL_SLOT_SIZE):
		@warning_ignore("integer_division")
		var row := i / GlobalInventory.SPELL_PAGE_SIZE
		ui_slots[i].slot_texture = _ACTIVE_FRAME if row == page else _INACTIVE_FRAME

func _unhandled_input(event: InputEvent) -> void:
	if not (%BestiaryPanel.visible or %MapPanel.visible):
		return
	# Reaching _unhandled_input at all means the click missed every Control (the open
	# panel included, since its mouse_filter stops input) — so any mouse press here is,
	# by construction, a click outside the pane. (The map consumes its own clicks for
	# pins/pan, so only clicks that miss it land here.) Wheel notches don't count as clicks,
	# so scrolling — over the map or the strip — never closes an open panel.
	var outside_click: bool = event is InputEventMouseButton and event.pressed \
			and event.button_index != MOUSE_BUTTON_WHEEL_UP \
			and event.button_index != MOUSE_BUTTON_WHEEL_DOWN
	# Web's Fullscreen API reserves Esc to exit fullscreen and can't be
	# preventDefault()'d, so sharing it with a UI action there is a losing fight —
	# skip the shortcut on web and rely on the button/outside-click instead.
	var menu_close := OS.get_name() != "Web" and event.is_action_pressed("menu")
	if outside_click or menu_close:
		%BestiaryPanel.hide()
		%MapPanel.hide()
		get_viewport().set_input_as_handled()

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
