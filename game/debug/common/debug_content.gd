class_name DebugContent
## Content-folder scanners shared by the debug tools (combat lab palettes, console
## give/spawn). Everything is discovered from disk so new items/enemies appear in the
## tools automatically — no hand-maintained lists.
extends RefCounted

const ITEM_DIRS := {
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
			# A spell folder also holds the bespoke casts its minions fire. Those are
			# ItemResources too, but nothing gives them to a player, so they carry no icon
			# — and an iconless entry has nothing to draw in a palette that shows no text.
			if item != null and item.icon != null:
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


## Enemy ids grouped by the biome whose rooms spawn them: [{label, ids}], in world order
## (sub-biomes sharing a BiomeDef.family merge into one entry, as they do in the bestiary).
## Every GenConfig in world_content/ is read, so a side dungeon groups like the main world.
## Enemies no spawn table claims — built, not placed yet — close the list under "other".
static func scan_enemy_groups() -> Array:
	var valid: Dictionary = {}
	for eid in scan_enemy_ids():
		if eid != &"placeholder":
			valid[eid] = true
	var by_label: Dictionary = {}   # label -> {enemy id: true}; insertion order = world order
	for path in scan_gen_configs():
		var cfg := load(path) as GenConfig
		if cfg == null:
			continue
		var label_of: Dictionary = {}
		for b in cfg.biomes:
			label_of[b.id] = b.family if b.family != &"" else b.id
		for rt in cfg.room_types:
			# A WORLD-unique room type names no owning biome; it spawns in each it allows.
			var biomes: Array = [rt.biome] if rt.biome != &"" else Array(rt.unique_allowed_biomes)
			for biome in biomes:
				var label: StringName = label_of.get(biome, biome)
				for entry in rt.enemies:
					for id in _entry_enemy_ids(entry):
						if valid.has(id):
							by_label.get_or_add(label, {})[id] = true
	var out: Array = []
	var claimed: Dictionary = {}
	for label in by_label:
		var ids: Array[StringName] = []
		for id in by_label[label]:
			ids.append(id)
			claimed[id] = true
		# StringName < compares pointers, not text — sort on the String form.
		ids.sort_custom(func(a, b): return String(a) < String(b))
		out.append({"label": label, "ids": ids})
	var rest: Array[StringName] = []
	for eid in valid:
		if not claimed.has(eid):
			rest.append(eid)
	rest.sort_custom(func(a, b): return String(a) < String(b))
	if not rest.is_empty():
		out.append({"label": &"other", "ids": rest})
	return out


## Both spawn-table shapes: a single type, or a mixed pack's members.
static func _entry_enemy_ids(entry: SpawnTableEntry) -> Array[StringName]:
	var out: Array[StringName] = []
	if entry == null:
		return out
	if entry.members.is_empty():
		if entry.enemy_id != &"":
			out.append(entry.enemy_id)
		return out
	for m in entry.members:
		if m != null and m.enemy_id != &"":
			out.append(m.enemy_id)
	return out


## Every world config: the main world plus the side dungeons (mycelium), sorted.
static func scan_gen_configs() -> PackedStringArray:
	var out: PackedStringArray = []
	for f in DirAccess.get_files_at("res://world_content/"):
		if f.ends_with("gen_config.tres"):
			out.append("res://world_content/" + f)
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
			var item := load(path) as ItemResource
			if item == null or item.icon == null:
				continue
			if itname == query:
				exact = item
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
	var slots: Array = []
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
