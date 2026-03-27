extends CanvasLayer

func _ready() -> void:
	GlobalEvent.player_max_health_changed.connect(_on_player_max_health_changed)
	GlobalEvent.player_health_changed.connect(_on_player_health_changed)
	GlobalEvent.player_max_mana_changed.connect(_on_player_max_mana_changed)
	GlobalEvent.player_mana_changed.connect(_on_player_mana_changed)
	GlobalEvent.player_skill_changed.connect(_on_player_skill_changed)
	GlobalEvent.player_speed_changed.connect(_on_player_speed_changed)

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

