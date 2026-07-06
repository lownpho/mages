extends CanvasLayer

func _ready() -> void:
	GlobalEvent.player_max_health_changed.connect(_on_player_max_health_changed)
	GlobalEvent.player_health_changed.connect(_on_player_health_changed)
	GlobalEvent.player_max_mana_changed.connect(_on_player_max_mana_changed)
	GlobalEvent.player_mana_changed.connect(_on_player_mana_changed)
	GlobalEvent.player_skill_changed.connect(_on_player_skill_changed)
	GlobalEvent.player_speed_changed.connect(_on_player_speed_changed)
	GlobalEvent.player_defence_changed.connect(_on_player_defence_changed)

	# Assign the ui_slots to the ui_slots
	var ui_slots = %Bag.get_children()
	for i in range(GlobalInventory.BAG_SIZE):
		ui_slots[i].slot = GlobalInventory.bag_slots.at(i)
	ui_slots = %EquipSpells.get_children()
	for i in range(GlobalInventory.SPELL_SLOT_SIZE):
		ui_slots[i].slot = GlobalInventory.spell_slots.at(i)
	%HatSlot.slot = GlobalInventory.hat_slot
	%RobeSlot.slot = GlobalInventory.robe_slot
	%WeaponSlot.slot = GlobalInventory.weapon_slot

	# Show the value overlay only while hovering the bar.
	_setup_bar_hover(%HealthBar, %HealthValue)
	_setup_bar_hover(%ManaBar, %ManaValue)

	%BestiaryButton.pressed.connect(func() -> void:
		%BestiaryPanel.visible = not %BestiaryPanel.visible)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") and %BestiaryPanel.visible:
		%BestiaryPanel.hide()
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

func _on_player_max_mana_changed(max_mana: int) -> void:
	%ManaBar.max_value = max_mana
	_refresh_bar_value(%ManaBar, %ManaValue)

func _on_player_mana_changed(mana: int) -> void:
	%ManaBar.value = mana
	_refresh_bar_value(%ManaBar, %ManaValue)

func _refresh_bar_value(bar: ProgressBar, label: Label) -> void:
	label.text = "%d/%d" % [bar.value, bar.max_value]

func _on_player_skill_changed(skill: int) -> void:
	%SkillValue.text = str(skill)

func _on_player_speed_changed(speed: int) -> void:
	%SpeedValue.text = str(speed)

func _on_player_defence_changed(defence: int) -> void:
	%DefenceValue.text = str(defence)
