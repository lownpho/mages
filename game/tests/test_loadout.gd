extends Node

# One tier per spell per LINE: blam1 and blam2 must never sit in the same line together,
# but moving one between slots (or swapping in another spell) stays legal — and the copy
# rule is per line, so the same spell in a different line is fine.

var fails: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _ready() -> void:
	var blam1 = load("res://characters/player/spells/blam/blam1.tres")
	var blam2 = load("res://characters/player/spells/blam/blam2.tres")
	var pew1 = load("res://characters/player/spells/pew/pew1.tres")
	var slots = GlobalInventory.slots

	slots.at(0).set_item(blam2)
	_check(not GlobalInventory.can_equip(blam1, slots.at(1)), "blam1 accepted next to blam2")
	_check(GlobalInventory.can_equip(pew1, slots.at(1)), "pew1 refused next to blam2")
	_check(GlobalInventory.can_equip(blam2, slots.at(1), slots.at(0)),
		"blam2 refused when moving between slots in its own line")
	_check(not GlobalInventory.can_equip(blam2, slots.at(1)),
		"a second copy of blam2 accepted in the same line")
	_check(GlobalInventory.can_equip(blam1, slots.at(0)), "blam1 refused into blam2's own slot")
	_check(GlobalInventory.can_equip(blam1, slots.at(GlobalInventory.LINE_SIZE)),
		"blam1 refused in a different line to blam2")
	_check(GlobalInventory.can_equip(blam2, slots.at(GlobalInventory.LINE_SIZE)),
		"a second copy of blam2 refused in a different line")

	# A pickup lands in the first line that will take it — line 0 already holds a blam.
	_check(GlobalInventory.first_slot_for(blam1) == slots.at(GlobalInventory.LINE_SIZE),
		"pickup did not skip past the line already holding blam")
	slots.at(0).clear_item()
	for i in GlobalInventory.SIZE:
		slots.at(i).set_item(blam2)
	_check(GlobalInventory.first_slot_for(blam1) == null,
		"pickup accepted a blam with every line already holding one")
	for i in GlobalInventory.SIZE:
		slots.at(i).clear_item()
	slots.at(0).set_item(blam2)

	# A slot dropped onto itself must not re-emit (it double-fired the analytics track).
	var emits := 0
	var counter := func(_s: GlobalInventory.Slot) -> void: emits += 1
	GlobalEvent.equipment_changed.connect(counter)
	GlobalInventory.swap_items(slots.at(0), slots.at(0))
	GlobalEvent.equipment_changed.disconnect(counter)
	_check(emits == 0, "self-swap emitted equipment_changed %d times" % emits)

	for i in GlobalInventory.SIZE:
		slots.at(i).clear_item()
	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
