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
	_check(exact != null and exact is BulletSpellResource, "find_item exact blam1")
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
	# The lab persists its loadout into the same user://debug_state.cfg the developer's own
	# lab session uses — snapshot it so the test doesn't wipe their kit.
	var stored := _snapshot_lab_loadout()
	var lab: Node2D = load("res://debug/combat_lab/combat_lab.tscn").instantiate()
	add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(lab._panel != null, "lab panel built")
	_check(lab._floor.get_used_cells().size() > 0, "lab floor generated")
	lab._brush = &"sproutling"
	lab._spawn_brush(Vector2(100, 0))
	await get_tree().process_frame
	_check(lab._enemies.get_child_count() == 1, "brush spawned a sproutling")
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
	# Spells that reach their victims by capability rather than by collision (Thwomp's
	# pulse, a spore cloud's tick) look up `hurtbox` on what they find in the target group.
	# A dummy with only a $Hurtbox node answers null and eats nothing — and the lab then
	# lies about the very spells it exists to tune.
	var dummy: Node = lab._enemies.get_child(0)
	_check(dummy.is_in_group("enemies") and dummy.get("hurtbox") != null,
			"dummy answers the hurtbox capability contract")
	_check(lab._walls.tile_set.get_physics_layers_count() > 0,
			"wall tileset carries collision (bullets/chasers see it)")
	lab._walls.clear()
	lab._wall_brush_size = 1
	lab._preset_box()
	_check(lab._walls.get_cell_source_id(Vector2i(0, -lab.ARENA_HALF_TILES.y)) != -1
			and lab._walls.get_cell_source_id(Vector2i.ZERO) == -1,
			"box preset walls the perimeter and leaves the interior open")
	var walled: int = lab._walls.get_used_cells().size()
	lab._paint_walls(Vector2(5, 5) * GameConstants.PX_PER_TILE, true)
	_check(lab._walls.get_used_cells().size() == walled + 1, "wall brush painted one cell")
	lab._paint_walls(Vector2(5, 5) * GameConstants.PX_PER_TILE, false)
	_check(lab._walls.get_used_cells().size() == walled, "wall brush erased the cell")
	lab._set_wall(Vector2i.ZERO, true)
	_check(lab._walls.get_cell_source_id(Vector2i.ZERO) == -1,
			"wall brush refuses to brick in the player")
	lab._walls.clear()
	lab._save_walls()

	var pew := DebugContent.find_item("pew1")
	lab._equip_item(pew)
	var slotted := false
	for slot in GlobalInventory.spell_slots.slots:
		if slot.item == pew:
			slotted = true
	_check(slotted, "palette click equipped the spell")
	var persisted := false
	for i in GlobalInventory.spell_slots.slots.size():
		if DebugState.get_value("combat_lab", "spell_%d" % i, "") == pew.resource_path:
			persisted = true
	_check(persisted, "equipping wrote the loadout to DebugState")
	GlobalInventory.reset()
	lab.queue_free()
	await get_tree().process_frame
	_restore_lab_loadout(stored)


## The lab state this test perturbs — the loadout slots ("spell_N"/"bag_N") and the painted
## arena ("walls") — as key -> value.
func _snapshot_lab_loadout() -> Dictionary:
	var out: Dictionary = {}
	for key in DebugState.keys("combat_lab"):
		if _is_lab_session_key(key):
			out[key] = DebugState.get_value("combat_lab", key)
	return out


func _restore_lab_loadout(stored: Dictionary) -> void:
	for key in DebugState.keys("combat_lab"):
		if _is_lab_session_key(key) and not stored.has(key):
			DebugState.erase("combat_lab", key)
	for key in stored:
		DebugState.set_value("combat_lab", key, stored[key])


static func _is_lab_session_key(key: String) -> bool:
	return key.begins_with("spell_") or key.begins_with("bag_") or key == "walls"


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
