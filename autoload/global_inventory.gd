extends Node

const BAG_SIZE = 6
const SPELL_SLOT_SIZE = 4

# ItemType.BAG is used as the slot category for bag slots — no item should ever have type BAG
enum ItemType {BAG, WEAPON, ROBE, HAT, SPELL, OTHER}

class Slot:
	var type: ItemType
	var item: ItemResource
	var compatibility_list: Array[ItemType] = []

	func _init(p_type: ItemType, p_compatibility_list: Array[ItemType] = [p_type]):
		type = p_type
		compatibility_list = p_compatibility_list
		item = null

	func can_place_item(p_item: ItemResource) -> bool:
		return p_item.get_item_type() in compatibility_list

	func set_item(p_item: ItemResource) -> bool:
		if not can_place_item(p_item):
			return false
		item = p_item
		_emit_changed()
		return true

	func clear_item() -> void:
		item = null
		_emit_changed()

	func _emit_changed() -> void:
		GlobalEvent.slot_updated.emit(self)
		if type == GlobalInventory.ItemType.WEAPON \
				or type == GlobalInventory.ItemType.HAT \
				or type == GlobalInventory.ItemType.ROBE:
			GlobalEvent.equipment_changed.emit(self)

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

	func at(p_index: int) -> Slot:
		if p_index < 0 or p_index >= slots.size():
			return null
		return slots[p_index]

	func add_at_first_empty(p_item: ItemResource) -> Slot:
		var index = first_empty()
		if index == -1:
			return null
		if slots[index].set_item(p_item):
			return slots[index]
		return null

	func add_at(p_index: int, p_item: ItemResource) -> bool:
		if at(p_index) == null:
			return false
		return slots[p_index].set_item(p_item)

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
	weapon_slot = Slot.new(ItemType.WEAPON)
	robe_slot = Slot.new(ItemType.ROBE)
	hat_slot = Slot.new(ItemType.HAT)
	bag_slots = ArraySlot.new(ItemType.BAG, BAG_SIZE, [ItemType.BAG, ItemType.WEAPON, ItemType.ROBE, ItemType.HAT, ItemType.SPELL])
	spell_slots = ArraySlot.new(ItemType.SPELL, SPELL_SLOT_SIZE)

# Swaps items between two slots atomically: both slot_updated (and equipment_changed
# if applicable) signals fire only after the swap is complete.
func swap_items(slot_a: Slot, slot_b: Slot) -> void:
	var tmp = slot_a.item
	slot_a.item = slot_b.item
	slot_b.item = tmp
	slot_a._emit_changed()
	slot_b._emit_changed()

func get_inventory_status() -> String:
	var output = ""
	output += "Weapon Slot: " + (str(weapon_slot.item.icon.resource_path) if weapon_slot.item else "Empty") + "\n"
	output += "Robe Slot: " + (str(robe_slot.item.icon.resource_path) if robe_slot.item else "Empty") + "\n"
	output += "Hat Slot: " + (str(hat_slot.item.icon.resource_path) if hat_slot.item else "Empty") + "\n"
	output += "Bag Slots:\n"
	for i in range(bag_slots.slots.size()):
		var slot = bag_slots.slots[i]
		output += "  Slot " + str(i) + ": " + (str(slot.item.icon.resource_path) if slot.item else "Empty") + "\n"
	output += "Spell Slots:\n"
	for i in range(spell_slots.slots.size()):
		var slot = spell_slots.slots[i]
		output += "  Slot " + str(i) + ": " + (str(slot.item.icon.resource_path) if slot.item else "Empty") + "\n"
	return output
