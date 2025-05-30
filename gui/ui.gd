extends CanvasLayer

func _ready() -> void:
	GlobalEvent.connect("player_max_health_changed", _on_player_max_health_changed)
	GlobalEvent.connect("player_health_changed", _on_player_health_changed)
	GlobalEvent.connect("player_max_mana_changed", _on_player_max_mana_changed)
	GlobalEvent.connect("player_mana_changed", _on_player_mana_changed)
	GlobalEvent.connect("player_skill_changed", _on_player_skill_changed)
	GlobalEvent.connect("player_speed_changed", _on_player_speed_changed)

	# Debug
	GlobalEvent.slot_updated.connect(_on_slot_updated)

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

func _on_player_max_health_changed(max_health: int) -> void:
	%HealthBar.max_value = max_health

func _on_player_health_changed(health: int) -> void:
	%HealthBar.value = health

func _on_player_max_mana_changed(max_mana: int) -> void:
	%ManaBar.max_value = max_mana

func _on_player_mana_changed(mana: int) -> void:
	%ManaBar.value = mana

func _on_player_skill_changed(skill: int) -> void:
	%SkillValue.text = str(skill)

func _on_player_speed_changed(speed: int) -> void:
	%SpeedValue.text = str(speed)

func _on_slot_updated(_slot: GlobalInventory.Slot) -> void:
	$DebugLabel.text = GlobalInventory.get_inventory_status()
