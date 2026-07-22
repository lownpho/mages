extends Node
## Headless bestiary smoke test: roster derivation, spawn-table-derived page grouping (biomes
## sharing a BiomeDef.family merge into one page), the kill→unlock flow through
## GlobalEvent.creature_died, summon exclusion, and the to_dict/restore save shape. Run:
##   godot --headless --path game res://tests/test_bestiary.tscn

func _ready() -> void:
	var fails: Array[String] = []

	# Kills/visits persist to user://bestiary.cfg and are loaded at _ready, so run against a clean
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
	# family "glade" so they merge into one page. Deepwood spawns nothing -> no page. Ordering
	# is commons alpha, rares, bosses last. ---
	var groups := GlobalBestiary.grouped_roster()
	var want_glade: Array[StringName] = [
		&"dirt_golem", &"hopper", &"mandrake", &"rosebud", &"seedling", &"sproutling",
		&"thornthrower", &"wasp",
		&"mandraker", &"viper",   # rares after the commons
		&"fae", &"thornmess",     # bosses last (one per sub-biome)
	]
	if groups.size() != 1:
		fails.append("expected the single merged glade page, got %d: %s" % [groups.size(), str(groups)])
	elif groups[0] != want_glade:
		fails.append("glade page %s != %s" % [str(groups[0]), str(want_glade)])
	var pages := GlobalBestiary.visible_pages()
	if not pages.is_empty():
		fails.append("pages visible before any visit/kill: %s" % str(pages))

	# filed_ids: distinct enemies across all pages (the whole-game completion denominator) —
	# a subset of the roster (unreachable enemies excluded), each counted once.
	var filed := GlobalBestiary.filed_ids()
	if filed.size() != want_glade.size():
		fails.append("filed_ids size %d != %d: %s" % [filed.size(), want_glade.size(), str(filed)])
	for id in filed:
		if not roster.has(id):
			fails.append("filed id not in roster: %s" % id)

	# --- section visibility: visiting EITHER merged sub-biome reveals the family page ---
	if not GlobalBestiary.visible_grouped_roster().is_empty():
		fails.append("sections visible before any visit/kill: %s" % str(GlobalBestiary.visible_grouped_roster()))
	GlobalEvent.biome_entered.emit(&"glade_veggie")
	var vis := GlobalBestiary.visible_grouped_roster()
	if vis.size() != 1 or not vis[0].has(&"thornmess"):
		fails.append("visiting glade_veggie should reveal the glade page, got %s" % str(vis))
	var page: Dictionary = GlobalBestiary.visible_pages()[0]
	if page["biome"] != &"glade":
		fails.append("merged page label %s != glade" % page["biome"])
	var want_bosses := [&"fae", &"thornmess"]  # a family page closes with every sub-biome's boss
	if page["bosses"] != want_bosses:
		fails.append("page bosses %s != %s" % [str(page["bosses"]), str(want_bosses)])

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

	# Killing an enemy of an unvisited page reveals it (fresh slate, no visits, one viper kill).
	GlobalBestiary.restore({})
	GlobalEvent.creature_died.emit(GlobalBestiary.load_data(&"viper"), Vector2.ZERO)
	if GlobalBestiary.visible_grouped_roster().size() != 1:
		fails.append("viper kill should reveal the glade page: %s" % str(GlobalBestiary.visible_grouped_roster()))
	# Killing a trackable-but-unfiled enemy records the kill but adds no page — it belongs to
	# no page's derived roster. (ent is gitignored WIP, so only assert when it's on disk.)
	if roster.has(&"ent"):
		GlobalEvent.creature_died.emit(GlobalBestiary.load_data(&"ent"), Vector2.ZERO)
		if not GlobalBestiary.is_unlocked(&"ent"):
			fails.append("ent kill not recorded")
		if GlobalBestiary.visible_grouped_roster().size() != 1:
			fails.append("unfiled ent kill should not add a section: %s" % str(GlobalBestiary.visible_grouped_roster()))

	# --- save shape ---
	GlobalEvent.biome_entered.emit(&"glade_start")
	var saved := GlobalBestiary.to_dict()
	GlobalBestiary.restore({})
	if GlobalBestiary.is_unlocked(&"viper"):
		fails.append("restore({}) did not clear kills")
	if not GlobalBestiary.visible_grouped_roster().is_empty():
		fails.append("restore({}) did not clear visited biomes")
	GlobalBestiary.restore(saved)
	if GlobalBestiary.kill_count(&"viper") != 1:
		fails.append("restore lost kill counts")
	if GlobalBestiary.visible_grouped_roster().size() != 1:
		fails.append("restore lost visited biomes")

	# Put the player's real progress back and reflush it (the kill/visit emits above overwrote
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
