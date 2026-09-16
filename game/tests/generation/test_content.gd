extends Node
## Headless tests for the content load pass: the shipped World loads clean, every content error is
## reported with its file and line, all of them in one pass, and discovery works on an export's
## remapped files. Run:
##   godot --headless --path game res://tests/generation/test_content.tscn

const SHIPPED := "res://generation/world/"
const FIXTURES := "res://tests/generation/fixtures/"
const THORNMESS := "res://characters/enemies/thornmess/thornmess_data.tres"

## Fixture under load_errors/ -> exactly the problems it reports, as [file relative to the fixture,
## line, text the message contains]. Line 0 means the problem has no line: a missing file.
const LOAD_ERRORS := {
	"parse_error": [["biomes/solo/zones/start.tres", 13, "Parse Error: Expected ','"]],
	"missing_file_reference": [["biomes/solo/biome.tres", 20, "referenced non-existent resource at: res://characters/enemies/moth/mothh_data.tres"]],
	"missing_id_reference": [["biomes/solo/zones/start.tres", 15, "Can't load cached ext-resource id: owll"]],
	"missing_files": [
		["biomes/lonely/zones/", 0, "Biome 'lonely' has no Zone files"],
		["biomes/orphan/biome.tres", 0, "missing: expected a BiomeResource"],
		["challenge_curve.tres", 0, "missing: expected a ChallengeCurveResource"],
	],
	"unknown_property": [
		["biomes/solo/biome.tres", 14, "'centered' is not a property of fixed_encounter_resource.gd"],
		["biomes/solo/zones/start.tres", 13, "'raers' is not a property of zone_resource.gd"],
	],
	"wrong_script": [["biomes/solo/zones/start.tres", 17, "is a BiomeResource, not a ZoneResource"]],
	"out_of_range": [
		["biomes/solo/biome.tres", 23, "room_size is 80, above its maximum 64"],
		["biomes/solo/zones/start.tres", 8, "route_rooms is 0, below its minimum 1"],
	],
	"topology_unlisted": [["world.tres", 10, "Biome 'extra' is neither on the Ideal path nor a Side biome"]],
	"topology_duplicate": [["world.tres", 10, "Biome 'solo' appears in the topology more than once"]],
	"side_parent_not_ideal": [["world.tres", 18, "Side biome 'pit' has parent 'cave', which is not on the Ideal path"]],
	"exit_challenge": [
		["biomes/low/biome.tres", 18, "exit_challenge 3 is below the 4 its parent 'solo' exits at"],
		["biomes/next/biome.tres", 18, "exit_challenge 4 doesn't rise above the 4 Biome 'next' starts at"],
	],
	"no_spawn_zone": [["world.tres", 10, "no Zone is the Spawn zone"]],
	"spawn_zone_misplaced": [["biomes/later/zones/start.tres", 10, "the Spawn zone must belong to the Ideal path's first Biome, not 'later'"]],
	"two_spawn_zones": [
		["biomes/solo/zones/also.tres", 10, "2 Zones are the Spawn zone (solo/also, solo/start)"],
		["biomes/solo/zones/start.tres", 10, "2 Zones are the Spawn zone (solo/also, solo/start)"],
	],
	"no_boss": [["biomes/solo/biome.tres", 9, "Biome 'solo' has no Boss"]],
	"leaderless_encounter": [["biomes/solo/zones/start.tres", 9, "a Rare has no leader"]],
	"entry_out_of_range": [
		["biomes/deep/biome.tres", 20, "snake enters at Challenge 2, outside the Biome's 4 to 8"],
		["biomes/solo/biome.tres", 20, "moth enters at Challenge 5, outside the Biome's 0 to 4"],
	],
	"duplicate_shared_enemy": [["biomes/solo/zones/start.tres", 15, "moth is already on the Biome's shared roster"]],
	"duplicate_roster_key": [["biomes/solo/biome.tres", 22, "roster lists moth_data.tres twice"]],
	"reveal_not_boss": [["biomes/solo/biome.tres", 20, "a Sign reveals viper, which leads no Boss or Miniboss"]],
	"quota_capacity": [["biomes/solo/zones/start.tres", 22, "room_count 4 cannot hold 3 route Rooms, 2 Rares and the Boss (needs 6)"]],
	"attachment_infeasible": [["world.tres", 23, "'solo' has 7 route Rooms, too few to attach 2 Side biomes 3 apart and 2 from either end (needs 8)"]],
	"curve_steps": [
		["challenge_curve.tres", 7, "encounters_per_tile needs a step at Challenge 0"],
		["challenge_curve.tres", 11, "types_per_encounter at Challenge 0 is 0, below 1"],
		["challenge_curve.tres", 13, "teach_dip is 0, below its minimum 1"],
	],
	"group_size": [
		["creatures/bad/bad_data.tres", 9, "group_max 2 is below group_min 3"],
		["creatures/bad/bad_data.tres", 10, "weight is 0, below its minimum 1"],
	],
	# Problems of every kind in five files, none hiding another.
	"aggregate": [
		["biomes/deep/biome.tres", 20, "snake enters at Challenge 2, outside the Biome's 4 to 8"],
		["biomes/deep/zones/broken.tres", 12, "Parse Error: Expected ':'"],
		["biomes/deep/zones/lost.tres", 14, "referenced non-existent resource at: res://characters/enemies/ghost/ghost_data.tres"],
		["biomes/solo/zones/start.tres", 14, "'raers' is not a property of zone_resource.gd"],
		["biomes/solo/zones/start.tres", 16, "moth is already on the Biome's shared roster"],
		["challenge_curve.tres", 13, "teach_dip is 0, below its minimum 1"],
	],
}

var _fails: Array[String] = []


func _ready() -> void:
	_test_shipped_world()
	_test_derived_totals()
	_test_load_errors()
	_test_exported_discovery()
	_test_inspector_ids()
	_test_saver_order(SHIPPED)
	_test_saver_order(FIXTURES + "small/")
	if _fails.is_empty():
		print("ALL PASS")
		get_tree().quit(0)
	else:
		for fail in _fails:
			print("  FAIL: ", fail)
		print("FAILED: %d" % _fails.size())
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fails.append(message)


func _test_shipped_world() -> void:
	var content := ContentLoader.load_content(SHIPPED)
	_check(content.is_valid(), "shipped World has problems:\n" + content.report())
	_check(content.ideal_path == [&"glade", &"deepwood", &"wastelands", &"fruit"], "Ideal path is %s" % [content.ideal_path])
	_check(content.parents == {&"hive": &"deepwood", &"mycelium": &"deepwood", &"moon": &"wastelands", &"hell": &"wastelands"},
			"Side biome parents are %s" % [content.parents])
	_check(content.biomes.size() == 8 and content.biome_ids().size() == 8, "expected 8 Biomes, each placed once")
	_check(content.spawn_zone == "glade/start", "Spawn zone is '%s'" % content.spawn_zone)
	_check(content.zone_ids(&"glade") == [&"main", &"start", &"veggie"], "Glade Zones are %s" % [content.zone_ids(&"glade")])
	_check(content.zone_ids(&"deepwood") == [&"main", &"mimic"], "Deepwood Zones are %s" % [content.zone_ids(&"deepwood")])
	_check(content.zone_count(&"mycelium") > 1, "Mycelium should be one Biome with several Zones")
	for placeholder: StringName in [&"wastelands", &"fruit", &"hive", &"moon", &"hell"]:
		var biome := content.biomes.get(placeholder) as BiomeResource
		_check(biome != null and content.zone_count(placeholder) == 1, "placeholder %s should have one Zone" % placeholder)
		_check(biome != null and biome.boss.leader.resource_path == THORNMESS, "placeholder %s's Boss should be thornmess" % placeholder)
	# Group size and weight default to 1-1 and 1 where an enemy doesn't author them.
	var owl: CreatureResource = load("res://characters/enemies/owl/owl_data.tres")
	var moth: CreatureResource = load("res://characters/enemies/moth/moth_data.tres")
	_check([owl.group_min, owl.group_max, owl.weight] == [1, 1, 1], "owl should keep the default group size and weight")
	_check([moth.group_min, moth.group_max] == [2, 3], "moth should author a group of 2-3")


## Zone counts and Room totals come from the Zone files alone.
func _test_derived_totals() -> void:
	var content := ContentLoader.load_content(FIXTURES + "small/")
	_check(content.is_valid(), "small fixture has problems:\n" + content.report())
	_check(content.biome_ids() == [&"meadow", &"forest", &"burrow", &"hollow"], "small fixture Biomes are %s" % [content.biome_ids()])
	_check(content.zone_count(&"forest") == 2, "forest should count 2 Zones")
	_check(content.route_rooms(&"forest") == 16, "forest route_rooms %d, want 10 + 6" % content.route_rooms(&"forest"))
	_check(content.room_count(&"forest") == 34, "forest room_count %d, want 20 + 14" % content.room_count(&"forest"))
	_check(content.world_room_count() == 64, "small World counts %d Rooms, want 64" % content.world_room_count())
	_check(content.lowest_challenge(&"forest") == 3 and content.lowest_challenge(&"burrow") == 3,
			"forest and its Side biomes should start from meadow's exit, 3")


func _test_load_errors() -> void:
	var cases := ResourceLoader.list_directory(FIXTURES + "load_errors/")
	for fixture: String in LOAD_ERRORS:
		_check(cases.has(fixture + "/"), "load_errors/%s is missing" % fixture)
	for entry in cases:
		_check(LOAD_ERRORS.has(entry.trim_suffix("/")), "load_errors/%s has no expected problems" % entry)
	for fixture: String in LOAD_ERRORS:
		var root := FIXTURES + "load_errors/" + fixture + "/"
		var content := ContentLoader.load_content(root)
		var expected: Array = LOAD_ERRORS[fixture]
		var unmatched := content.errors.duplicate()
		for want: Array in expected:
			var match_index := -1
			for i in unmatched.size():
				var error: ContentError = unmatched[i]
				if error.file == root + want[0] and error.line == want[1] and error.message.contains(want[2]):
					match_index = i
					break
			if match_index < 0:
				_fails.append("%s: missing %s:%d: %s" % [fixture, want[0], want[1], want[2]])
			else:
				unmatched.remove_at(match_index)
		for error: ContentError in unmatched:
			_fails.append("%s: unexpected %s" % [fixture, error])


## An export keeps only .remap files where its resources were. Discovery must still find them.
func _test_exported_discovery() -> void:
	var root := FIXTURES + "remapped/"
	_check(DirAccess.get_files_at(root + "biomes/solo/zones") == PackedStringArray(["start.tres.remap"]),
			"the remapped fixture should hold only .remap files")
	var content := ContentLoader.load_content(root)
	_check(content.is_valid(), "remapped fixture has problems:\n" + content.report())
	_check(content.biome_ids() == [&"solo"] and content.zone_ids(&"solo") == [&"start"], "remapped content wasn't discovered")
	_check(content.spawn_zone == "solo/start", "remapped fixture's Spawn zone is '%s'" % content.spawn_zone)


## Ext and sub-resource ids the inspector generates, uids and metadata load like hand-written ones.
func _test_inspector_ids() -> void:
	var content := ContentLoader.load_content(FIXTURES + "inspector_ids/")
	_check(content.is_valid(), "inspector_ids fixture has problems:\n" + content.report())
	var zone := content.zones.get(&"solo", {}).get(&"start") as ZoneResource
	_check(zone != null and zone.rares.size() == 1 and zone.rares[0].escorts.size() == 1, "inspector_ids Rare didn't load")


## Hand-written content is already in the saver's order, so an inspector save only adds uids: ext ids
## sorted, one dictionary entry per line, defaults left out. The save goes in place, because ext ids
## are remembered per file, and the original text is always put back.
func _test_saver_order(root: String) -> void:
	var content := ContentLoader.load_content(root)
	var files: Array[String] = [root + ContentLoader.WORLD_FILE, root + ContentLoader.CURVE_FILE]
	for biome_id in content.biomes:
		files.append("%sbiomes/%s/%s" % [root, biome_id, ContentLoader.BIOME_FILE])
		for zone_id in content.zone_ids(biome_id):
			files.append("%sbiomes/%s/zones/%s.tres" % [root, biome_id, zone_id])
	for path in files:
		var before := FileAccess.get_file_as_string(path)
		var result := ResourceSaver.save(load(path), path)
		var after := FileAccess.get_file_as_string(path)
		if after == before:
			_check(result == OK, "%s: save failed with %s" % [path, error_string(result)])
			continue
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(before)
		restore.close()
		var old_lines := before.split("\n")
		var new_lines := after.split("\n")
		var line := 0
		while line < mini(old_lines.size(), new_lines.size()) and old_lines[line] == new_lines[line]:
			line += 1
		_fails.append("%s:%d: a save rewrites it\n    written: %s\n    saved:   %s" % [path, line + 1,
				old_lines[line] if line < old_lines.size() else "", new_lines[line] if line < new_lines.size() else ""])
