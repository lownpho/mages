extends Node
## Headless bestiary smoke test: roster derivation, spawn-table-derived biome grouping, the
## kill→unlock flow through GlobalEvent.creature_died, summon exclusion, and the to_dict/restore
## save shape. Run:
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
	if not roster.has(&"owl"):
		fails.append("roster missing owl: " + str(roster))
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

	# --- biome grouping is DERIVED from the room spawn tables (not a stored biome field): each
	# enemy files onto the biome whose rooms spawn it; ordering is commons alpha, rare, boss last.
	# Enemies in no spawn table (e.g. ent/snake today) are unreachable, so they aren't filed. ---
	var groups := GlobalBestiary.grouped_roster()
	if groups.size() != 2:
		fails.append("expected glade+deepwood groups, got %d: %s" % [groups.size(), str(groups)])
	else:
		var want_glade: Array[StringName] = [
			&"dirt_golem", &"hopper", &"mandrake", &"seedling", &"sproutling", &"wasp",
			&"viper",  # rare after the commons
			&"fae",    # boss last
		]
		if groups[0] != want_glade:
			fails.append("glade group %s != %s" % [str(groups[0]), str(want_glade)])
		var want_deepwood: Array[StringName] = [&"owl", &"stalker"]
		if groups[1] != want_deepwood:
			fails.append("deepwood group %s != %s" % [str(groups[1]), str(want_deepwood)])

	# filed_ids: distinct enemies across all pages (the whole-game completion denominator) —
	# a subset of the roster (unreachable enemies excluded), each counted once.
	var filed := GlobalBestiary.filed_ids()
	if filed.size() != 10:
		fails.append("filed_ids size %d != 10: %s" % [filed.size(), str(filed)])
	for id in filed:
		if not roster.has(id):
			fails.append("filed id not in roster: %s" % id)

	# --- section visibility: nothing discovered yet -> no sections ---
	if not GlobalBestiary.visible_grouped_roster().is_empty():
		fails.append("sections visible before any visit/kill: %s" % str(GlobalBestiary.visible_grouped_roster()))
	GlobalEvent.biome_entered.emit(&"glade")
	var vis := GlobalBestiary.visible_grouped_roster()
	if vis.size() != 1 or not vis[0].has(&"fae"):
		fails.append("visiting glade should reveal exactly the glade section, got %s" % str(vis))

	# --- kill -> unlock flow ---
	var unlocked: Array = []
	var updated: Array = []
	GlobalEvent.bestiary_entry_unlocked.connect(func(id: StringName) -> void: unlocked.append(id))
	GlobalEvent.bestiary_updated.connect(func(id: StringName, k: int) -> void: updated.append([id, k]))
	var owl := GlobalBestiary.load_data(&"owl")
	GlobalEvent.creature_died.emit(owl, Vector2.ZERO)
	GlobalEvent.creature_died.emit(owl, Vector2.ZERO)
	if not GlobalBestiary.is_unlocked(&"owl"):
		fails.append("owl not unlocked after kill")
	if GlobalBestiary.kill_count(&"owl") != 2:
		fails.append("owl kill_count %d != 2" % GlobalBestiary.kill_count(&"owl"))
	if unlocked != [&"owl"]:
		fails.append("unlock emitted %s, want [owl] exactly once" % str(unlocked))
	if updated != [[&"owl", 1], [&"owl", 2]]:
		fails.append("updated emitted %s" % str(updated))

	# A summon's injected CreatureResource has no resource_path -> never tracked.
	GlobalEvent.creature_died.emit(CreatureResource.new(), Vector2.ZERO)
	if updated.size() != 2:
		fails.append("pathless CreatureResource was tracked")

	# Killing an enemy of an unvisited biome reveals that biome (owl -> deepwood).
	if GlobalBestiary.visible_grouped_roster().size() != 2:
		fails.append("owl kill should reveal deepwood: %s" % str(GlobalBestiary.visible_grouped_roster()))
	# Killing a trackable-but-unfiled enemy (golem is in no spawn table) records the kill but
	# adds no page — it belongs to no biome's derived roster.
	GlobalEvent.creature_died.emit(GlobalBestiary.load_data(&"golem"), Vector2.ZERO)
	if not GlobalBestiary.is_unlocked(&"golem"):
		fails.append("golem kill not recorded")
	if GlobalBestiary.visible_grouped_roster().size() != 2:
		fails.append("unfiled golem kill should not add a section: %s" % str(GlobalBestiary.visible_grouped_roster()))

	# --- save shape ---
	var saved := GlobalBestiary.to_dict()
	GlobalBestiary.restore({})
	if GlobalBestiary.is_unlocked(&"owl"):
		fails.append("restore({}) did not clear kills")
	if not GlobalBestiary.visible_grouped_roster().is_empty():
		fails.append("restore({}) did not clear visited biomes")
	GlobalBestiary.restore(saved)
	if GlobalBestiary.kill_count(&"owl") != 2:
		fails.append("restore lost kill counts")
	if GlobalBestiary.visible_grouped_roster().size() != 2:
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
