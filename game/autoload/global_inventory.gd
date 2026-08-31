extends Node

# The inventory is two containers. The spell row is SPELL_SLOTS slots, one per cast button
# (cast1..cast4, left to right) — those four spells are what the mage can cast, and the only
# ones whose stat modifiers count. The bag is BAG_ROWS x BAG_COLUMNS of plain storage: it
# holds whatever else the run has picked up, casting nothing and granting nothing, until the
# player drags something out of it into the spell row.
const SPELL_SLOTS = 4
const BAG_COLUMNS = 4
const BAG_ROWS = 2
const BAG_SIZE = BAG_COLUMNS * BAG_ROWS

# ItemType.BAG is the bag slots' own category — it accepts everything, and no item ever
# carries it as its own type.
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
		# Only the spell row feeds the mage's stats, so a bag shuffle doesn't recompute them.
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

var spell_slots: ArraySlot
var bag_slots: ArraySlot

func _ready() -> void:
	spell_slots = ArraySlot.new(ItemType.SPELL, SPELL_SLOTS)
	bag_slots = ArraySlot.new(ItemType.BAG, BAG_SIZE,
			[ItemType.BAG, ItemType.SPELL, ItemType.OTHER])

## Slot behind a cast button (0..SPELL_SLOTS-1).
func spell_slot(index: int) -> Slot:
	return spell_slots.at(index)

## Every slot, spell row first then the bag. This is the canonical order — pickups fill it,
## saves iterate it — so slot N means the same place every time.
func all_slots() -> Array[Slot]:
	var out: Array[Slot] = []
	out.append_array(spell_slots.slots)
	out.append_array(bag_slots.slots)
	return out

# Empty every slot. Called when starting a new game so nothing carries over from a
# previous run. Each clear re-emits slot_updated / equipment_changed, so any live UI and
# player stats reset too.
func reset() -> void:
	for slot in all_slots():
		slot.clear_item()

# A spell's id is its folder, so blam1/blam2/blam3 are all "blam" — only one tier
# of a spell may sit in the spell row at a time.
func spell_family(item: ItemResource) -> String:
	if item == null or item.resource_path == "":
		return ""
	return item.resource_path.get_base_dir().get_file()

# Whether the player may drop this item into that slot: type compatibility plus the
# one-tier-per-spell rule, which binds the spell row only — the bag will hold any pile of
# duplicates. `source` is the slot the item is leaving, excluded from the scan: since a
# duplicate copy is the very same .tres, matching on the resource is no longer enough to
# tell a move from a second copy. Bypassed on purpose by the console, the combat lab and
# save loading — this is the player-facing restriction only.
func can_equip(item: ItemResource, target: Slot, source: Slot = null) -> bool:
	if not target.can_place_item(item):
		return false
	if target.type != ItemType.SPELL:
		return true
	var family := spell_family(item)
	for slot in spell_slots.slots:
		if slot == target or slot == source or slot.item == null:
			continue
		if spell_family(slot.item) == family:
			return false
	return true

# First slot a picked-up item may legally land in — the spell row before the bag, so a spell
# walked over goes straight onto a cast button while there's room for it. Null when the whole
# inventory is full.
func first_slot_for(item: ItemResource) -> Slot:
	for slot in all_slots():
		if slot.item == null and can_equip(item, slot):
			return slot
	return null

# First empty slot anywhere, spell row before bag, ignoring the one-tier-per-spell rule —
# the debug path (console `give`, the combat lab palette), which is not bound by a
# player-facing restriction.
func add_at_first_empty(item: ItemResource) -> Slot:
	var slot := spell_slots.add_at_first_empty(item)
	return slot if slot != null else bag_slots.add_at_first_empty(item)

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
