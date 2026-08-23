extends Node

# The inventory is the loadout: LINES rows of LINE_SIZE spells, all carried, one line
# live. The cast buttons drive the active line's slots; switching lines is the only way
# to reach the others, and it costs a rooted wind-up (see PlayerCastInput).
const LINE_SIZE = 4
const LINES = 3
const SIZE = LINE_SIZE * LINES

enum ItemType {SPELL, OTHER}

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

var slots: ArraySlot

## Which line (row of LINE_SIZE slots) the cast buttons drive.
var active_line: int = 0

func _ready() -> void:
	slots = ArraySlot.new(ItemType.SPELL, SIZE, [ItemType.SPELL, ItemType.OTHER])

## Slot behind a cast button (0..LINE_SIZE-1) on the active line.
func active_slot(index: int) -> Slot:
	return slots.at(active_line * LINE_SIZE + index)

## The line a slot index belongs to.
func line_of(index: int) -> int:
	@warning_ignore("integer_division")
	return index / LINE_SIZE

func set_line(line: int) -> void:
	line = posmod(line, LINES)
	if line == active_line:
		return
	active_line = line
	GlobalEvent.active_line_changed.emit(active_line)

func cycle_line() -> void:
	set_line(active_line + 1)

# Empty every slot. Called when starting a new game so nothing carries over from a
# previous run. Each clear re-emits slot_updated / equipment_changed, so any live UI and
# player stats reset too.
func reset() -> void:
	for slot in slots.slots:
		slot.clear_item()
	set_line(0)

# A spell's id is its folder, so blam1/blam2/blam3 are all "blam" — only one tier
# of a spell may sit in a given line at a time.
func spell_family(item: ItemResource) -> String:
	if item == null or item.resource_path == "":
		return ""
	return item.resource_path.get_base_dir().get_file()

# Whether the player may drop this item into that slot: type compatibility plus the
# one-tier-per-spell rule, scoped to the target's own line — the same spell may sit in
# two different lines, it just can't be castable twice off one line. `source` is the slot
# the item is leaving, excluded from the scan: since a duplicate copy is the very same
# .tres, matching on the resource is no longer enough to tell a move from a second copy.
# Bypassed on purpose by the console, the combat lab and save loading — this is the
# player-facing restriction only.
func can_equip(item: ItemResource, target: Slot, source: Slot = null) -> bool:
	if not target.can_place_item(item):
		return false
	var target_index := slots.slots.find(target)
	if target_index == -1:
		return true
	var family := spell_family(item)
	for i in slots.slots.size():
		var slot := slots.at(i)
		if i == target_index or slot == source or slot.item == null:
			continue
		if line_of(i) != line_of(target_index):
			continue
		if spell_family(slot.item) == family:
			return false
	return true

# First slot a picked-up item may legally land in, scanning line by line — null when the
# inventory is full or every line with room already holds that spell.
func first_slot_for(item: ItemResource) -> Slot:
	for slot in slots.slots:
		if slot.item == null and can_equip(item, slot):
			return slot
	return null

# Swaps items between two slots atomically: both slot_updated (and equipment_changed
# if applicable) signals fire only after the swap is complete.
func swap_items(slot_a: Slot, slot_b: Slot) -> void:
	# Dropping a slot onto itself is a no-op, not two changes of the same slot.
	if slot_a == slot_b:
		return
	var tmp = slot_a.item
	slot_a.item = slot_b.item
	slot_b.item = tmp
	slot_a._emit_changed()
	slot_b._emit_changed()
