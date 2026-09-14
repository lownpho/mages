extends Node
## Headless smoke test for the debug tooling: the content scanners the console and the World debug
## layer's Combat tab read, DebugState persistence and the console command dispatcher. Run as a
## scene (autoloads):
##   godot --headless --path game res://tests/debug/test_debug_tools.tscn

var _failures := 0


func _ready() -> void:
	_test_scan_items()
	_test_scan_enemies()
	_test_find_item()
	_test_debug_state()
	_test_console()
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
			# Keeps a minion's bespoke cast (poot_shot, blops_ring, …) out of the palettes.
			_check(entry["item"].icon != null, "scanned %s has an icon" % entry["name"])


func _test_scan_enemies() -> void:
	var ids := DebugContent.scan_enemy_ids()
	_check(not ids.is_empty(), "scan_enemy_ids found enemies")
	_check(&"sproutling" in ids, "sproutling is in the roster")
	_check(DebugContent.enemy_scene(&"sproutling") != null, "sproutling scene loads")
	_check(DebugContent.enemy_scene(&"no_such_enemy") == null, "unknown enemy is null")


func _test_find_item() -> void:
	var exact := DebugContent.find_item("blam1")
	_check(exact != null and exact is BulletSpellResource, "find_item exact blam1")
	_check(DebugContent.find_item("zzz_no_such_item") == null, "find_item miss is null")
	_check(DebugContent.find_item("poot_shot") == null, "find_item skips a bespoke minion cast")


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
	for cmd in ["help", "fps", "unknowncmd"]:
		console._run(cmd)
	_check(not console._lines.is_empty(), "console produced output")
	# Movement, seeds and loadouts moved to the World debug layer.
	for cmd in ["warp", "tp", "pos", "heal", "seed", "kit"]:
		console._run(cmd)
		_check(String(console._lines[-1]).begins_with("unknown command"), "console still answers %s" % cmd)
