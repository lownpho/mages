extends Node
## Headless grimoire smoke test: entry discovery from the spell folders (shipped spell files only,
## in book order), the pickup→learn flow through GlobalEvent.item_picked_up, the tutorial sandbox
## and non-player spells staying out of it, and the to_dict/restore save shape. Run:
##   godot --headless --path game res://tests/test_grimoire.tscn

const SPELLS := "res://characters/player/spells/"

# A member, not a local: the handler below appends to it from a lambda.
var learned_events: Array = []

func _ready() -> void:
	var fails: Array[String] = []

	# Learned entries persist to user://grimoire.cfg and are loaded at _ready, so run against a clean
	# in-memory slate for determinism — then restore the player's real progress at the end so a
	# headless test run never clobbers their save.
	var real_save := GlobalGrimoire.to_dict()
	GlobalGrimoire.restore({})

	# --- discovery: every shipped spell file, and nothing that only lives beside one ---
	var entries := GlobalGrimoire.entries()
	for id: StringName in [&"pew1", &"pew3_insect", &"zoing2", &"charge_dash2", &"nope", &"heal1"]:
		if not entries.has(id):
			fails.append("entries() is missing %s" % id)
	for id: StringName in [&"poot_shot", &"poot_shot_fed", &"blops_ring", &"fireball_1_explosion",
			&"ploop_mine_frames", &"oop_mine_frames"]:
		if entries.has(id):
			fails.append("%s is effect data, not a spell" % id)

	# Book order: spells alphabetically, a spell's files in tier order with the side tier last.
	var pew := entries.find(&"pew1")
	if entries.slice(pew, pew + 4) != Array([&"pew1", &"pew2", &"pew3", &"pew3_insect"], TYPE_STRING_NAME, &"", null):
		fails.append("pew's entries are out of order: %s" % str(entries.slice(pew, pew + 4)))
	var families: Array = entries.map(func(id: StringName) -> String:
		return GlobalInventory.spell_family(GlobalGrimoire.load_spell(id)))
	for i in range(1, families.size()):
		if families[i - 1] > families[i]:
			fails.append("entries not grouped alphabetically by spell at %s" % entries[i])
			break

	# Every entry is a real player spell with an icon: the book draws nothing else, and a missing
	# one is a hole, not an error. Its id round-trips through entry_id, which a pickup is matched by.
	for id in entries:
		var spell := GlobalGrimoire.load_spell(id)
		if spell == null:
			fails.append("%s does not load as a SpellResource" % id)
			continue
		if spell.icon == null:
			fails.append("%s has no icon" % id)
		if spell.effect_scene == null:
			fails.append("%s has no effect scene, so it isn't a working spell" % id)
		if GlobalGrimoire.entry_id(spell) != id:
			fails.append("entry_id(%s) is '%s'" % [id, GlobalGrimoire.entry_id(spell)])

	# --- pickup -> learn ---
	GlobalEvent.grimoire_entry_learned.connect(func(id: StringName) -> void: learned_events.append(id))
	# A loose slot, assigned directly: set_item would emit slot_updated and poke the run's autosave.
	var slot := GlobalInventory.Slot.new(GlobalInventory.ItemType.BAG)
	slot.item = load(SPELLS + "pew/pew3_insect.tres")
	GlobalEvent.item_picked_up.emit(slot)
	GlobalEvent.item_picked_up.emit(slot)
	if not GlobalGrimoire.is_learned(&"pew3_insect"):
		fails.append("pew3_insect not learned after a pickup")
	if GlobalGrimoire.is_learned(&"pew3"):
		fails.append("picking up pew3_insect learned pew3 too")
	if learned_events != [&"pew3_insect"]:
		fails.append("learned emitted %s, want [pew3_insect] exactly once" % str(learned_events))

	# An enemy's bespoke cast is a SpellResource too, but no entry; a pathless spell (console,
	# combat lab) is nothing at all.
	for item: ItemResource in [load("res://characters/enemies/wasp/wasp_spell.tres"), SpellResource.new()]:
		slot.item = item
		GlobalEvent.item_picked_up.emit(slot)
	if learned_events.size() != 1:
		fails.append("a non-player spell was learned: %s" % str(learned_events))

	# The tutorial's pickups are not discoveries.
	GameState.sandbox = true
	slot.item = load(SPELLS + "blam/blam1.tres")
	GlobalEvent.item_picked_up.emit(slot)
	GameState.sandbox = false
	if GlobalGrimoire.is_learned(&"blam1"):
		fails.append("a pickup inside the sandbox was learned")
	GlobalEvent.item_picked_up.emit(slot)
	if not GlobalGrimoire.is_learned(&"blam1"):
		fails.append("the same pickup outside the sandbox was not learned")

	# Completion counts learned entries only.
	if GlobalGrimoire.completion(entries) != Vector2i(2, entries.size()):
		fails.append("completion %s, want (2, %d)" % [GlobalGrimoire.completion(entries), entries.size()])

	# --- save shape: through a real ConfigFile, as the save file stores it ---
	var cfg := ConfigFile.new()
	cfg.set_value("grimoire", "learned", GlobalGrimoire.to_dict()["learned"])
	var reread := ConfigFile.new()
	reread.parse(cfg.encode_to_text())
	GlobalGrimoire.restore({})
	if GlobalGrimoire.is_learned(&"blam1"):
		fails.append("restore({}) did not clear learned entries")
	GlobalGrimoire.restore({"learned": reread.get_value("grimoire", "learned", [])})
	if not GlobalGrimoire.is_learned(&"blam1") or not GlobalGrimoire.is_learned(&"pew3_insect"):
		fails.append("a save round trip lost learned entries: %s" % str(GlobalGrimoire.to_dict()))

	# Put the player's real progress back and reflush it (the pickups above overwrote the save file).
	GlobalGrimoire.restore(real_save)
	GlobalGrimoire._save()

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
