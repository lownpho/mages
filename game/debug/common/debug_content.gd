class_name DebugContent
## Content-folder scanners shared by the debug tools (combat lab palettes, console
## give/spawn). Everything is discovered from disk so new items/enemies appear in the
## tools automatically — no hand-maintained lists.
extends RefCounted

const ITEM_DIRS := {
	"weapons": "res://characters/player/weapons",
	"hats": "res://characters/player/hats",
	"robes": "res://characters/player/robes",
	"spells": "res://characters/player/spells",
}
const ENEMIES_DIR := "res://characters/enemies"


## category -> Array of {name: String (file basename), item: ItemResource}, each category
## sorted by name. Categories follow ITEM_DIRS keys.
static func scan_items() -> Dictionary:
	var out: Dictionary = {}
	for cat in ITEM_DIRS:
		var entries: Array = []
		for path in _walk_tres(ITEM_DIRS[cat]):
			var res := load(path)
			var item := res as ItemResource
			if item != null:
				entries.append({"name": path.get_file().trim_suffix(".tres"), "item": item})
		entries.sort_custom(func(a, b): return a["name"] < b["name"])
		out[cat] = entries
	return out


## Enemy ids: every characters/enemies/<id>/ folder with a matching <id>.tscn, sorted.
static func scan_enemy_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var d := DirAccess.open(ENEMIES_DIR)
	if d == null:
		return out
	for sub in d.get_directories():
		if ResourceLoader.exists("%s/%s/%s.tscn" % [ENEMIES_DIR, sub, sub]):
			out.append(StringName(sub))
	out.sort()
	return out


static func enemy_scene(enemy_id: StringName) -> PackedScene:
	var path := "%s/%s/%s.tscn" % [ENEMIES_DIR, enemy_id, enemy_id]
	if ResourceLoader.exists(path):
		return load(path)
	return null


## Item whose file basename matches `query` — exact match first, then unique prefix,
## then unique substring. Null when nothing (or more than one thing) matches.
static func find_item(query: String) -> ItemResource:
	var exact: ItemResource = null
	var partial: Array = []
	for cat in ITEM_DIRS:
		for path in _walk_tres(ITEM_DIRS[cat]):
			var itname := path.get_file().trim_suffix(".tres")
			if itname == query:
				exact = load(path) as ItemResource
			elif itname.begins_with(query) or itname.contains(query):
				partial.append(path)
	if exact != null:
		return exact
	if partial.size() == 1:
		return load(partial[0]) as ItemResource
	return null


## Re-read every slotted item's .tres from disk (CACHE_MODE_REPLACE) and re-slot it, so an
## external stat edit shows up in a running session — set_item re-fires the whole
## equip/stat/UI pipeline. Returns how many items were reloaded.
static func reload_slotted_items() -> int:
	var n := 0
	var slots: Array = [GlobalInventory.weapon_slot, GlobalInventory.hat_slot,
			GlobalInventory.robe_slot]
	slots.append_array(GlobalInventory.bag_slots.slots)
	slots.append_array(GlobalInventory.spell_slots.slots)
	for slot in slots:
		if slot.item == null or slot.item.resource_path == "":
			continue
		var fresh := ResourceLoader.load(slot.item.resource_path, "",
				ResourceLoader.CACHE_MODE_REPLACE) as ItemResource
		if fresh != null:
			slot.set_item(fresh)
			n += 1
	return n


## All .tres file paths under a directory, recursively, sorted for determinism.
static func _walk_tres(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".tres"):
			out.append(dir_path + "/" + f)
	for sub in d.get_directories():
		out.append_array(_walk_tres(dir_path + "/" + sub))
	out.sort()
	return out
