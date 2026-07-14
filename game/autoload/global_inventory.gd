extends Node

const BAG_SIZE = 9
# The spell loadout: SPELL_PAGES pages of SPELL_PAGE_SIZE slots each. The cast
# buttons (LMB/RMB/Space) drive the active page's slots; SHIFT cycles pages.
const SPELL_PAGE_SIZE = 3
const SPELL_PAGES = 2
const SPELL_SLOT_SIZE = SPELL_PAGE_SIZE * SPELL_PAGES

# ItemType.BAG is used as the slot category for bag slots — no item should ever have type BAG.
enum ItemType {BAG, SPELL, OTHER}

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
		if type == GlobalInventory.ItemType.SPELL:
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

var bag_slots: ArraySlot
var spell_slots: ArraySlot

## Which spell page (row of SPELL_PAGE_SIZE slots) the cast buttons drive.
var active_spell_page: int = 0

func _ready() -> void:
	bag_slots = ArraySlot.new(ItemType.BAG, BAG_SIZE, [ItemType.BAG, ItemType.SPELL, ItemType.OTHER])
	spell_slots = ArraySlot.new(ItemType.SPELL, SPELL_SLOT_SIZE)

## Slot behind a cast button (0..SPELL_PAGE_SIZE-1) on the active page.
func active_spell_slot(index: int) -> Slot:
	return spell_slots.at(active_spell_page * SPELL_PAGE_SIZE + index)

func cycle_spell_page() -> void:
	active_spell_page = (active_spell_page + 1) % SPELL_PAGES
	GlobalEvent.spell_page_changed.emit(active_spell_page)

# Empty every slot — bag and spells. Called when starting a new game so nothing
# carries over from a previous run. Each clear re-emits slot_updated /
# equipment_changed, so any live UI and player stats reset too.
func reset() -> void:
	for slot in bag_slots.slots:
		slot.clear_item()
	for slot in spell_slots.slots:
		slot.clear_item()
	if active_spell_page != 0:
		active_spell_page = 0
		GlobalEvent.spell_page_changed.emit(0)

func get_equipment_slot_for_item(item: ItemResource) -> Slot:
	if item.get_item_type() == ItemType.SPELL:
		var idx = spell_slots.first_empty()
		return spell_slots.at(idx if idx != -1 else 0)
	return null

# Swaps items between two slots atomically: both slot_updated (and equipment_changed
# if applicable) signals fire only after the swap is complete.
func swap_items(slot_a: Slot, slot_b: Slot) -> void:
	var tmp = slot_a.item
	slot_a.item = slot_b.item
	slot_b.item = tmp
	slot_a._emit_changed()
	slot_b._emit_changed()
