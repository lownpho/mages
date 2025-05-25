extends Node

const MAX_BAG_SIZE = 6
const MAX_SPELL_SLOT_SIZE = 4

const SLOT_SIZES = {
	GlobalDefs.ItemType.BAG: MAX_BAG_SIZE,
	GlobalDefs.ItemType.SPELL: MAX_SPELL_SLOT_SIZE,
}

var slots: Dictionary = {}

class SlotPosition:
	var type: GlobalDefs.ItemType
	var index: int
	
	func _init(p_type: GlobalDefs.ItemType, p_index: int = 0):
		type = p_type
		index = p_index
	
	func equals(other: SlotPosition) -> bool:
		return type == other.type && index == other.index

class ItemData:
	var type: GlobalDefs.ItemType
	var scene: PackedScene
	var texture: Texture2D
	
	func _init(p_type: GlobalDefs.ItemType, p_scene: PackedScene, p_texture: Texture2D):
		type = p_type
		scene = p_scene
		texture = p_texture

func _ready() -> void:
	# Initialize arrays to null values
	slots[GlobalDefs.ItemType.BAG] = []
	slots[GlobalDefs.ItemType.BAG].resize(MAX_BAG_SIZE)
	slots[GlobalDefs.ItemType.SPELL] = []
	slots[GlobalDefs.ItemType.SPELL].resize(MAX_SPELL_SLOT_SIZE)
	
	slots[GlobalDefs.ItemType.WEAPON] = null
	slots[GlobalDefs.ItemType.ROBE] = null
	slots[GlobalDefs.ItemType.HAT] = null

func is_array_slot(type: GlobalDefs.ItemType) -> bool:
	return type in [GlobalDefs.ItemType.BAG, GlobalDefs.ItemType.SPELL]

func can_place_item(item: ItemData, slot: SlotPosition) -> bool:
	# be liberal in what you accept, conservative in what you do. I guess...
	if item  == null:
		return true
	
	if is_array_slot(slot.type):
		var max_size = SLOT_SIZES[slot.type]
		if slot.type == GlobalDefs.ItemType.SPELL:
			return slot.index < max_size && item.type == GlobalDefs.ItemType.SPELL
		# Allow everything in bag slots
		return slot.index < max_size
	
	return item.type == slot.type

func get_item_at(slot: SlotPosition) -> ItemData:
	if is_array_slot(slot.type):
		var array = slots[slot.type]
		return array[slot.index] if slot.index < array.size() else null
	return slots[slot.type]

# Use sparingly. This erases the item at position.
# There are dedicated functions to equip or swap items
func set_item(item: ItemData, slot: SlotPosition) -> void:
	if not can_place_item(item, slot):
		return
		
	if is_array_slot(slot.type):
		slots[slot.type][slot.index] = item

	else:
		# Does comparing items work here?
		var old_item = slots[slot.type]
		if old_item != item:
			slots[slot.type] = item
	GlobalEvent.inventory_updated.emit(slot)

# Allow swaps with null items destination
func swap_items(from_slot: SlotPosition, to_slot: SlotPosition) -> bool:
	var from_item = get_item_at(from_slot)
	var to_item = get_item_at(to_slot)

	if from_item == null:
		return false
	
	if not can_place_item(from_item, to_slot) or not can_place_item(to_item, from_slot):
		return false
	
	# For a brief moment the first item will be duplicated. Whatever
	set_item(to_item, from_slot)
	set_item(from_item, to_slot)

	return true

# Try to equip/unequip items between bag and active slots
# This is complete bullshit
func swap_bag_and_active(to_slot: SlotPosition, from_slot: SlotPosition) -> bool:
	var to_item = get_item_at(to_slot)
	var from_item = get_item_at(from_slot)

	var bag_slot
	var active_slot
	var bag_item
	var active_item
	
	# Validate slot types and assign active and bag slots/items
	# at least one of the slots must be a bag but not both
	if from_slot.type == GlobalDefs.ItemType.BAG:
		bag_slot = from_slot
		active_slot = to_slot
		bag_item = from_item
		active_item = to_item
	elif to_slot.type == GlobalDefs.ItemType.BAG:
		bag_slot = to_slot
		active_slot = from_slot
		bag_item = to_item
		active_item = from_item
	else:
		return false
		
	# Handle different cases:
	# 1. Unequip: Active slot has item, bag slot empty
	# 2. Equip: Active slot empty, bag has item
	# 3. Swap: Both slots have items
	if active_item and not bag_item:
		# Working around the swap_items checks... :(
		var result = swap_items(active_slot, bag_slot)
		GlobalEvent.item_unequipped.emit(bag_slot)
		return result
	elif not active_item and bag_item:
		var result = swap_items(bag_slot, active_slot)
		GlobalEvent.item_equipped.emit(active_slot)
		return result
	elif active_item and bag_item:
		var result = swap_items(bag_slot, active_slot)
		GlobalEvent.item_unequipped.emit(bag_slot)
		GlobalEvent.item_equipped.emit(active_slot)
		return result
		
	return false


func add_item_to_bag(item: ItemData) -> bool:
	# Try to find first empty bag slot
	for i in range(MAX_BAG_SIZE):
		if slots[GlobalDefs.ItemType.BAG][i] == null:
			set_item(item, SlotPosition.new(GlobalDefs.ItemType.BAG, i))	
			return true
	return false

func get_empty_bag_slot() -> SlotPosition:
	for i in range(MAX_BAG_SIZE):
		if slots[GlobalDefs.ItemType.BAG][i] == null:
			return SlotPosition.new(GlobalDefs.ItemType.BAG, i)
	return null

func get_inventory_status() -> String:
	var output = "=== INVENTORY STATUS ===\n"
	
	# Array-based slots (Bag and Spells)
	for type in slots.keys():
		if is_array_slot(type):
			output += "\n%s:\n" % GlobalDefs.ItemType.keys()[type]
			for i in range(slots[type].size()):
				var item = slots[type][i]
				output += "[%d] %s\n" % [i, item.scene.resource_path.get_file() if item else "---"]
	
	# Equipment slots
	output += "\nEQUIPMENT:\n"
	for type in slots.keys():
		if not is_array_slot(type):
			var item = slots[type]
			output += "%s: %s\n" % [
				GlobalDefs.ItemType.keys()[type],
				item.scene.resource_path.get_file() if item else "---"
			]
	
	output += "====================="
	return output
