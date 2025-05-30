extends Node

const BAG_SIZE = 6
const SPELL_SLOT_SIZE = 4

# Not sure of the usefullness of the ItemType BAG
enum ItemType {BAG, WEAPON, ROBE, HAT, SPELL, OTHER}

class ItemData:
	var type: ItemType
	var scene: PackedScene
	var texture: Texture2D
	
	func _init(p_type: ItemType, p_scene: PackedScene, p_texture: Texture2D):
		type = p_type
		scene = p_scene
		texture = p_texture

# The use of index here is borderline criminal
class Slot:
	var type: ItemType
	var item: ItemData
	var compatibility_list: Array[ItemType] = []
	var index = -1
	
	func _init(p_type: ItemType, p_compatibility_list: Array[ItemType] = [p_type]):
		type = p_type
		compatibility_list = p_compatibility_list
		item = null
	
	func can_place_item(p_item: ItemData) -> bool:
		return p_item.type in compatibility_list
	
	# Having the index here is a big forced
	func set_item(p_item: ItemData, p_index: int = -1) -> bool:
		if can_place_item(p_item):
			item = p_item
			index = p_index
			GlobalEvent.slot_updated.emit(self)
			return true
		return false
	
	func clear_item() -> void:
		item = null
		GlobalEvent.slot_updated.emit(self)

class ArraySlot:
	var slots: Array[Slot] = []
	
	func _init(p_type: ItemType, p_size: int, p_compatibility_list: Array[ItemType] = [p_type]):
		for i in range(p_size):
			slots.append(Slot.new(p_type, p_compatibility_list))
	
	func first_empty() -> int:
		for i in range(slots.size()):
			if slots[i].item == null:
				return i
		return -1
	
	# Meant to be called externally, directly checking on the slots is faster in here
	func at(p_index: int) -> Slot:
		if p_index < 0 or p_index >= slots.size():
			return null
		return slots[p_index]
	
	func add_at_first_empty(p_item: ItemData) -> Slot:
		var index = first_empty()
		if index == -1:
			return null
		
		if slots[index].set_item(p_item, index):
			return slots[index]
		return null
	
	func add_at(p_index: int, p_item: ItemData) -> bool:
		if at(p_index) == null:
			return false
		
		return slots[p_index].set_item(p_item, p_index)
	
	func remove_at(p_index: int) -> bool:
		if at(p_index) == null or at(p_index).item == null:
			return false
		
		slots[p_index].clear_item()
		return true

var weapon_slot: Slot
var robe_slot: Slot
var hat_slot: Slot
var bag_slots: ArraySlot
var spell_slots: ArraySlot

func _ready() -> void:
	# Initialize arrays to null values
	weapon_slot = Slot.new(ItemType.WEAPON)
	robe_slot = Slot.new(ItemType.ROBE)
	hat_slot = Slot.new(ItemType.HAT)
	bag_slots = ArraySlot.new(ItemType.BAG, BAG_SIZE, [ItemType.BAG, ItemType.WEAPON, ItemType.ROBE, ItemType.HAT, ItemType.SPELL])
	spell_slots = ArraySlot.new(ItemType.SPELL, SPELL_SLOT_SIZE)

# Public API
# Hmm everything can be handled in slots then

func get_inventory_status() -> String:
	var output = ""
	output += "Weapon Slot: " + (str(weapon_slot.item.texture.resource_path) if weapon_slot.item else "Empty") + "\n"
	output += "Robe Slot: " + (str(robe_slot.item.texture.resource_path) if robe_slot.item else "Empty") + "\n"
	output += "Hat Slot: " + (str(hat_slot.item.texture.resource_path) if hat_slot.item else "Empty") + "\n"
	output += "Bag Slots:\n"
	for i in range(bag_slots.slots.size()):
		var slot = bag_slots.slots[i]
		output += "  Slot " + str(i) + ": " + (str(slot.item.texture.resource_path) if slot.item else "Empty") + "\n"
	output += "Spell Slots:\n"
	for i in range(spell_slots.slots.size()):
		var slot = spell_slots.slots[i]
		output += "  Slot " + str(i) + ": " + (str(slot.item.texture.resource_path) if slot.item else "Empty") + "\n"
	return output
