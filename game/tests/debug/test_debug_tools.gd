extends Node
## Headless smoke test for the debug tooling: the content scanners the combat lab /
## console palettes are generated from, DebugState persistence, the console command
## dispatcher, and end-to-end drives of the combat lab (spawn/freeze/kill/equip) and the
## worldgen debug tool (drill-down, streaming, drop-in player, seed history). Run as a
## scene (autoloads):
##   godot --headless --path game res://tests/debug/test_debug_tools.tscn

var _failures := 0


func _ready() -> void:
	_test_scan_items()
	_test_scan_enemies()
	_test_find_item()
	_test_debug_state()
	_test_console()
	await _test_combat_lab()
	await _test_worldgen_debug()
	if _failures == 0:
		print("ALL PASS")
	else:
		print("FAILED: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: " + what)


func _test_scan_items() -> void:
	var items := DebugContent.scan_items()
	for cat in ["spells"]:
		_check(items.has(cat) and not items[cat].is_empty(), "scan_items has %s" % cat)
	for cat in items:
		for entry in items[cat]:
			_check(entry["item"] is ItemResource, "scanned %s is an ItemResource" % entry["name"])


func _test_scan_enemies() -> void:
	var ids := DebugContent.scan_enemy_ids()
	_check(not ids.is_empty(), "scan_enemy_ids found enemies")
	_check(&"wolf" in ids, "wolf is in the roster")
	_check(DebugContent.enemy_scene(&"wolf") != null, "wolf scene loads")
	_check(DebugContent.enemy_scene(&"no_such_enemy") == null, "unknown enemy is null")


func _test_find_item() -> void:
	var exact := DebugContent.find_item("blam1")
	_check(exact != null and exact is WeaponSpellResource, "find_item exact blam1")
	_check(DebugContent.find_item("zzz_no_such_item") == null, "find_item miss is null")


func _test_debug_state() -> void:
	DebugState.set_value("test", "roundtrip", Vector2i(4, 7))
	_check(DebugState.get_value("test", "roundtrip", Vector2i.ZERO) == Vector2i(4, 7),
			"DebugState roundtrip")
	DebugState.erase("test", "roundtrip")
	_check(DebugState.get_value("test", "roundtrip", null) == null, "DebugState erase")


func _test_console() -> void:
	var console := get_node_or_null("/root/DebugConsole")
	_check(console != null, "console autoload present")
	if console == null:
		return
	# Commands that need no player must not error and must answer something.
	for cmd in ["help", "fps", "seed", "unknowncmd"]:
		console._run(cmd)
	_check(not console._lines.is_empty(), "console produced output")
	console._run("seed 424242")
	_check(GameState.active_seed == 424242, "console seed command sets GameState")
	GameState.active_seed = 0


func _test_combat_lab() -> void:
	var lab: Node2D = load("res://debug/combat_lab/combat_lab.tscn").instantiate()
	add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(lab._panel != null, "lab panel built")
	_check(lab._floor.get_used_cells().size() > 0, "lab floor generated")
	lab._brush = &"wolf"
	lab._spawn_brush(Vector2(100, 0))
	await get_tree().process_frame
	_check(lab._enemies.get_child_count() == 1, "brush spawned a wolf")
	lab._set_frozen(lab._enemies.get_child(0), true)
	lab._kill_all(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(lab._enemies.get_child_count() == 0, "clear despawned everything")
	lab._brush = lab.DUMMY_ID
	lab._spawn_brush(Vector2(0, 50))
	await get_tree().process_frame
	_check(lab._enemies.get_child_count() == 1 and "max_health" in lab._enemies.get_child(0),
			"dummy spawned with health dial")
	var pew := DebugContent.find_item("pew1")
	lab._equip_item(pew)
	var slotted := false
	for slot in GlobalInventory.spell_slots.slots:
		if slot.item == pew:
			slotted = true
	_check(slotted, "palette click equipped the spell")
	GlobalInventory.reset()
	lab.queue_free()
	await get_tree().process_frame


func _test_worldgen_debug() -> void:
	var wg: Node2D = load("res://debug/worldgen/worldgen_debug.tscn").instantiate()
	add_child(wg)
	await get_tree().process_frame
	wg._apply_seed(777)
	_check(wg.spec != null, "layout built for seed 777")
	wg._select_biome(Vector2i.ZERO)
	wg._switch_view(2)
	_check(wg.current_view == 2, "biome view active")
	wg._drill_in()
	_check(wg.current_view == 3, "drill entered room view")
	_check(wg._room_view._out != null, "room view holds a real RoomOutput")
	wg._teleport_to_selection()
	_check(wg.current_view == 4, "teleport landed in fly view")
	for _i in 5:
		await get_tree().process_frame
	_check(wg._streamer.loaded_chunks() > 0, "fly view streamed chunks")
	wg._toggle_drop_in()
	_check(wg._player != null, "drop-in player spawned")
	_check(wg._player.debug_never_die, "drop-in player cannot wipe the save")
	await get_tree().process_frame
	wg._toggle_drop_in()
	_check(wg._player == null, "drop-in player returned to the fly cam")
	wg._drill_out()
	_check(wg.current_view == 3, "esc backed out to room view")
	wg._apply_seed(888)
	wg._history_step(-1)
	_check(wg.world_seed == 777, "seed history steps back")
	wg._history_step(1)
	_check(wg.world_seed == 888, "seed history steps forward")
	wg.queue_free()
	await get_tree().process_frame
