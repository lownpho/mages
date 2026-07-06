extends Node
## Headless bestiary smoke test: roster derivation, the kill→unlock flow through
## GlobalEvent.creature_died, summon exclusion, and the to_dict/restore save shape. Run:
##   godot --headless --path game res://tests/test_bestiary.tscn

func _ready() -> void:
	var fails: Array[String] = []

	# --- roster ---
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
		else:
			if data.icon == null:
				fails.append("no bestiary icon on %s" % id)
			if data.biome == &"":
				fails.append("no bestiary biome on %s" % id)

	# --- biome grouping: wired biomes first (world order), commons alpha, rare then boss last ---
	var groups := GlobalBestiary.grouped_roster()
	if groups.size() < 2:
		fails.append("expected at least glade+deepwood groups, got %d" % groups.size())
	else:
		var glade: Array[StringName] = groups[0]
		var want_glade: Array[StringName] = [
			&"dirt_golem", &"hopper", &"mandrake", &"seedling", &"sproutling", &"wasp",
			&"viper",  # rare after the commons
			&"fae",    # boss last
		]
		if glade != want_glade:
			fails.append("glade group %s != %s" % [str(glade), str(want_glade)])
		var deepwood: Array[StringName] = groups[1]
		var want_deepwood: Array[StringName] = [&"owl", &"snake", &"stalker", &"thornback"]
		if deepwood != want_deepwood:
			fails.append("deepwood group wrong: %s" % str(deepwood))
	var grouped_total := 0
	for g in groups:
		grouped_total += g.size()
	if grouped_total != roster.size():
		fails.append("grouped roster loses entries: %d != %d" % [grouped_total, roster.size()])

	# --- section visibility: nothing discovered yet -> no sections ---
	if not GlobalBestiary.visible_grouped_roster().is_empty():
		fails.append("sections visible before any visit/kill: %s" % str(GlobalBestiary.visible_grouped_roster()))
	GlobalEvent.biome_entered.emit(&"glade")
	var vis := GlobalBestiary.visible_grouped_roster()
	if vis.size() != 1 or (vis.size() == 1 and not vis[0].has(&"fae")):
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

	# Killing an enemy of an unvisited section reveals it (owl -> deepwood), and labels
	# that aren't walkable biomes surface the same way (golem -> dungeon).
	if GlobalBestiary.visible_grouped_roster().size() != 2:
		fails.append("owl kill should reveal deepwood: %s" % str(GlobalBestiary.visible_grouped_roster()))
	GlobalEvent.creature_died.emit(GlobalBestiary.load_data(&"golem"), Vector2.ZERO)
	if GlobalBestiary.visible_grouped_roster().size() != 3:
		fails.append("golem kill should reveal the dungeon section")

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
	if GlobalBestiary.visible_grouped_roster().size() != 3:
		fails.append("restore lost visited biomes")

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
