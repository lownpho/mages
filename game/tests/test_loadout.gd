extends Node

# One tier per spell in the SPELL ROW: blam1 and blam2 must never sit on two cast buttons
# together, but moving one between slots (or swapping in another spell) stays legal. The bag
# is unrestricted — it will carry any pile of tiers and duplicates.

var fails: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _ready() -> void:
	var blam1 = load("res://characters/player/spells/blam/blam1.tres")
	var blam2 = load("res://characters/player/spells/blam/blam2.tres")
	var pew1 = load("res://characters/player/spells/pew/pew1.tres")
	var spells = GlobalInventory.spell_slots
	var bag = GlobalInventory.bag_slots

	spells.at(0).set_item(blam2)
	_check(not GlobalInventory.can_equip(blam1, spells.at(1)), "blam1 accepted next to blam2")
	_check(GlobalInventory.can_equip(pew1, spells.at(1)), "pew1 refused next to blam2")
	_check(GlobalInventory.can_equip(blam2, spells.at(1), spells.at(0)),
		"blam2 refused when moving between cast slots")
	_check(not GlobalInventory.can_equip(blam2, spells.at(1)),
		"a second copy of blam2 accepted in the spell row")
	_check(GlobalInventory.can_equip(blam1, spells.at(0)), "blam1 refused into blam2's own slot")
	_check(GlobalInventory.can_equip(blam1, bag.at(0)),
		"blam1 refused into the bag while blam2 is cast-ready")
	_check(GlobalInventory.can_equip(blam2, bag.at(0)),
		"a second copy of blam2 refused by the bag")

	# A pickup fills the spell row first, then the bag — and the row already holds a blam,
	# so another tier of it skips straight past the free cast buttons.
	_check(GlobalInventory.first_slot_for(pew1) == spells.at(1),
		"pickup did not take the first free cast slot")
	_check(GlobalInventory.first_slot_for(blam1) == bag.at(0),
		"pickup did not skip the spell row already holding blam")
	for slot in GlobalInventory.all_slots():
		slot.set_item(blam2)
	_check(GlobalInventory.first_slot_for(blam1) == null,
		"pickup accepted a blam with the whole inventory full")
	for slot in GlobalInventory.all_slots():
		slot.clear_item()
	spells.at(0).set_item(blam2)

	# A slot dropped onto itself must not re-emit (it double-fired the analytics track).
	var emits := 0
	var counter := func(_s: GlobalInventory.Slot) -> void: emits += 1
	GlobalEvent.equipment_changed.connect(counter)
	GlobalInventory.swap_items(spells.at(0), spells.at(0))
	GlobalEvent.equipment_changed.disconnect(counter)
	_check(emits == 0, "self-swap emitted equipment_changed %d times" % emits)

	# Only the spell row is equipment: a bag edit must not claim the mage's stats changed.
	emits = 0
	GlobalEvent.equipment_changed.connect(counter)
	bag.at(0).set_item(pew1)
	bag.at(0).clear_item()
	GlobalEvent.equipment_changed.disconnect(counter)
	_check(emits == 0, "a bag edit emitted equipment_changed %d times" % emits)

	for slot in GlobalInventory.all_slots():
		slot.clear_item()
	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
