extends Node

# One tier per spell in the loadout: blam1 and blam2 must never sit in the spell
# slots together, but moving one between slots (or swapping in another spell) stays legal.

var fails: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _ready() -> void:
	var blam1 = load("res://characters/player/spells/blam/blam1.tres")
	var blam2 = load("res://characters/player/spells/blam/blam2.tres")
	var pew1 = load("res://characters/player/spells/pew/pew1.tres")
	var slots = GlobalInventory.spell_slots

	slots.at(0).set_item(blam2)
	_check(not GlobalInventory.can_equip(blam1, slots.at(1)), "blam1 accepted next to blam2")
	_check(GlobalInventory.can_equip(pew1, slots.at(1)), "pew1 refused next to blam2")
	_check(GlobalInventory.can_equip(blam2, slots.at(1)), "blam2 refused when moving slots")
	_check(GlobalInventory.can_equip(blam1, slots.at(0)), "blam1 refused into blam2's own slot")
	_check(GlobalInventory.can_equip(blam1, GlobalInventory.bag_slots.at(0)), "bag refused blam1")
	_check(GlobalInventory.get_equipment_slot_for_item(blam1) == slots.at(0),
		"auto-equip did not target blam2's slot")

	# A slot dropped onto itself must not re-emit (it double-fired the analytics track).
	var emits := 0
	var counter := func(_s: GlobalInventory.Slot) -> void: emits += 1
	GlobalEvent.equipment_changed.connect(counter)
	GlobalInventory.swap_items(slots.at(0), slots.at(0))
	GlobalEvent.equipment_changed.disconnect(counter)
	_check(emits == 0, "self-swap emitted equipment_changed %d times" % emits)

	for i in GlobalInventory.SPELL_SLOT_SIZE:
		slots.at(i).clear_item()
	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
