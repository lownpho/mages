extends Node
## Headless bestiary smoke test: roster derivation, spawn-table-derived page grouping (biomes
## sharing a BiomeDef.family merge into one page, every page in the book from the start), the
## kill→unlock flow through GlobalEvent.creature_died, summon exclusion, and the to_dict/restore
## save shape. Run:
##   godot --headless --path game res://tests/test_bestiary.tscn

func _ready() -> void:
	var fails: Array[String] = []

	# Kills persist to user://bestiary.cfg and are loaded at _ready, so run against a clean
	# in-memory slate for determinism — then restore the player's real progress at the end so a
	# headless test run never clobbers their save.
	var real_save := GlobalBestiary.to_dict()
	GlobalBestiary.restore({})

	# --- roster: every enemy folder with a <id>_data.tres, alphabetical ---
	var roster := GlobalBestiary.roster()
	if roster.is_empty():
		fails.append("roster is empty")
	for id: StringName in [&"sproutling", &"mandraker", &"thornmess"]:
		if not roster.has(id):
			fails.append("roster missing %s: %s" % [id, str(roster)])
	if roster.has(&"placeholder") or roster.has(&"behaviours"):
		fails.append("roster contains untrackable folders: " + str(roster))
	for i in range(1, roster.size()):
		if String(roster[i - 1]) > String(roster[i]):
			fails.append("roster not sorted: " + str(roster))
			break
	for id in roster:
		var data := GlobalBestiary.load_data(id)
		if data == null:
			fails.append("no CreatureResource for %s" % id)
		elif data.icon == null:
			fails.append("no bestiary icon on %s" % id)

	# --- page grouping is DERIVED from the room spawn tables (not a stored biome field): each
	# enemy files onto the page whose rooms spawn it, and glade_start + glade_veggie share
	# family "glade" so they merge into one page — as do deepwood + deepwood_mimic. The mycelium
	# page proves the walk reaches a DUNGEON: its config hangs off a door, and its enemies live
	# on the per-floor configs under that. Ordering is commons alpha, rares, bosses last. ---
	var pages := GlobalBestiary.pages()
	var want_glade: Array[StringName] = [
		&"dirt_golem", &"hopper", &"mandrake", &"rosebud", &"seedling", &"sproutling",
		&"thornthrower", &"wasp",
		&"mandraker", &"viper",   # rares after the commons
		&"fae", &"thornmess",     # bosses last (one per sub-biome)
	]
	var want_deepwood: Array[StringName] = [
		&"ash_snake", &"bramble_stalker", &"bristlestone", &"cinderstone", &"coral_snake",
		&"grimling", &"mole", &"moon_moth", &"moss_golem", &"moth", &"needle_moth",
		&"owl", &"shade", &"shard_grimling", &"snake", &"stalker", &"thornback",
		&"wisp_grimling",
		&"adder", &"elder_stalker", &"great_owl", &"grimlord", &"razorback", &"umbra",
		&"gnarlking",
	]
	var want_mycelium: Array[StringName] = [
		&"bloatcap", &"clustercap", &"gapcap", &"mould_golem", &"normiecap", &"puffcap",
		&"ringcap", &"rollcap", &"shellcap", &"spiralcap", &"sporefly", &"sporespitter",
		&"burrower", &"deathcap", &"maulcap",
	]
	var want_pages := [want_glade, want_deepwood, want_mycelium]
	if pages.size() != want_pages.size():
		fails.append("expected %d pages, got %d: %s" % [want_pages.size(), pages.size(), str(pages)])
	else:
		for i in want_pages.size():
			if pages[i]["ids"] != want_pages[i]:
				fails.append("page %d %s != %s" % [i, str(pages[i]["ids"]), str(want_pages[i])])

	# filed_ids: distinct enemies across all pages (the whole-game completion denominator) —
	# a subset of the roster (unreachable enemies excluded), each counted once.
	var filed := GlobalBestiary.filed_ids()
	var want_filed := want_glade.size() + want_deepwood.size() + want_mycelium.size()
	if filed.size() != want_filed:
		fails.append("filed_ids size %d != %d: %s" % [filed.size(), want_filed, str(filed)])
	for id in filed:
		if not roster.has(id):
			fails.append("filed id not in roster: %s" % id)

	# The merged family page is labelled with the family, and titled by the one sub-biome that
	# authors a display_name. A page with none falls back to its label capitalised.
	var page: Dictionary = pages[0]
	if page["biome"] != &"glade":
		fails.append("merged page label %s != glade" % page["biome"])
	var want_titles := ["The Glade", "Deepwood", "Mycelium"]
	for i in want_titles.size():
		if pages[i]["title"] != want_titles[i]:
			fails.append("page %d title '%s' != '%s'" % [i, pages[i]["title"], want_titles[i]])

	# --- kill -> unlock flow ---
	var unlocked: Array = []
	var updated: Array = []
	GlobalEvent.bestiary_entry_unlocked.connect(func(id: StringName) -> void: unlocked.append(id))
	GlobalEvent.bestiary_updated.connect(func(id: StringName, k: int) -> void: updated.append([id, k]))
	var wasp := GlobalBestiary.load_data(&"wasp")
	GlobalEvent.creature_died.emit(wasp, Vector2.ZERO)
	GlobalEvent.creature_died.emit(wasp, Vector2.ZERO)
	if not GlobalBestiary.is_unlocked(&"wasp"):
		fails.append("wasp not unlocked after kill")
	if GlobalBestiary.kill_count(&"wasp") != 2:
		fails.append("wasp kill_count %d != 2" % GlobalBestiary.kill_count(&"wasp"))
	if unlocked != [&"wasp"]:
		fails.append("unlock emitted %s, want [wasp] exactly once" % str(unlocked))
	if updated != [[&"wasp", 1], [&"wasp", 2]]:
		fails.append("updated emitted %s" % str(updated))

	# A summon's injected CreatureResource has no resource_path -> never tracked.
	GlobalEvent.creature_died.emit(CreatureResource.new(), Vector2.ZERO)
	if updated.size() != 2:
		fails.append("pathless CreatureResource was tracked")

	# Completion counts only unlocked entries, so a fresh slate reads 0/N and one kill reads 1/N.
	GlobalBestiary.restore({})
	if GlobalBestiary.completion(page["ids"]) != Vector2i(0, page["ids"].size()):
		fails.append("fresh slate completion %s" % str(GlobalBestiary.completion(page["ids"])))
	GlobalEvent.creature_died.emit(GlobalBestiary.load_data(&"viper"), Vector2.ZERO)
	if GlobalBestiary.completion(page["ids"]) != Vector2i(1, page["ids"].size()):
		fails.append("viper kill completion %s" % str(GlobalBestiary.completion(page["ids"])))
	# Killing a trackable-but-unfiled enemy records the kill but counts toward no page — it
	# belongs to no page's derived roster. (ent is gitignored WIP, so only assert when on disk.)
	if roster.has(&"ent"):
		GlobalEvent.creature_died.emit(GlobalBestiary.load_data(&"ent"), Vector2.ZERO)
		if not GlobalBestiary.is_unlocked(&"ent"):
			fails.append("ent kill not recorded")
		if GlobalBestiary.completion(GlobalBestiary.filed_ids()).x != 1:
			fails.append("unfiled ent kill should not count toward completion")

	# --- save shape ---
	var saved := GlobalBestiary.to_dict()
	GlobalBestiary.restore({})
	if GlobalBestiary.is_unlocked(&"viper"):
		fails.append("restore({}) did not clear kills")
	GlobalBestiary.restore(saved)
	if GlobalBestiary.kill_count(&"viper") != 1:
		fails.append("restore lost kill counts")

	# Put the player's real progress back and reflush it (the kill emits above overwrote
	# the save file mid-test).
	GlobalBestiary.restore(real_save)
	GlobalBestiary._save()

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
