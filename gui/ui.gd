extends CanvasLayer


func _ready() -> void:
	GlobalEvent.connect("player_max_health_changed", _on_player_max_health_changed)
	GlobalEvent.connect("player_health_changed", _on_player_health_changed)
	GlobalEvent.connect("player_max_mana_changed", _on_player_max_mana_changed)
	GlobalEvent.connect("player_mana_changed", _on_player_mana_changed)
	GlobalEvent.connect("player_skill_changed", _on_player_skill_changed)
	GlobalEvent.connect("player_speed_changed", _on_player_speed_changed)

	# Initialize all the slots to their default values. This is a bit of a hack
	# but it works for now. No idea how to do this better at the moment.
	var slots = %Bag.get_children()
	for i in range(GlobalInventory.MAX_BAG_SIZE):
		slots[i].item_position = GlobalInventory.SlotPosition.new(GlobalDefs.ItemType.BAG, i)
	slots = %EquipSpells.get_children()
	for i in range(GlobalInventory.MAX_SPELL_SLOT_SIZE):
		slots[i].item_position = GlobalInventory.SlotPosition.new(GlobalDefs.ItemType.SPELL, i)
	%HatSlot.item_position = GlobalInventory.SlotPosition.new(GlobalDefs.ItemType.HAT, 0)
	%RobeSlot.item_position = GlobalInventory.SlotPosition.new(GlobalDefs.ItemType.ROBE, 0)
	%WeaponSlot.item_position = GlobalInventory.SlotPosition.new(GlobalDefs.ItemType.WEAPON, 0)

	GlobalEvent.inventory_updated.connect(_on_inventory_updated)

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

func _on_inventory_updated(slot: GlobalInventory.SlotPosition) -> void:
	# GlobalInventory.print_inventory()
	print("Inventory updated: index ", slot.index, " type ", slot.type)
	$DebugLabel.text = GlobalInventory.get_inventory_status()
	match slot.type:
		GlobalDefs.ItemType.BAG:
			var slots = %Bag.get_children()
			if slot.index < slots.size():
				slots[slot.index].update(slot)
		GlobalDefs.ItemType.SPELL:
			var slots = %EquipSpells.get_children()
			if slot.index < slots.size():
				slots[slot.index].update(slot)
		GlobalDefs.ItemType.HAT:
			%HatSlot.update(slot)
		GlobalDefs.ItemType.ROBE:
			%RobeSlot.update(slot)
		GlobalDefs.ItemType.WEAPON:
			%WeaponSlot.update(slot)
	

# Debug
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		# # Test item swap
		# var from_slot = GlobalInventory.SlotPosition.new(GlobalDefs.ItemType.BAG, randi_range(0, 5))
		# var to_slot = GlobalInventory.SlotPosition.new(GlobalDefs.ItemType.BAG, randi_range(0, 5))
		# print("Swapping items from ", from_slot.index, " to ", to_slot.index)
		# if GlobalInventory.swap_items(from_slot, to_slot):
		# 	print("Swapped items successfully!")
		# else:
		# 	print("Failed to swap items.")

		# equip/unequip item
		var from_slot = GlobalInventory.SlotPosition.new(GlobalDefs.ItemType.BAG, randi_range(0, 5))
		var to_slot = GlobalInventory.SlotPosition.new(GlobalDefs.ItemType.WEAPON, 0)
		print("Equipping item from ", from_slot.index, " to ", to_slot.index)
		if GlobalInventory.equip_item(from_slot, to_slot):
			print("Equipped item successfully!")
		else:
			print("Failed to equip item.")
