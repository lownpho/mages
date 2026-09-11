extends Node

## Grimoire progress tracker: which spells the mage has learned. Every spell the game ships is in
## the book from the start as a silhouette, and an entry is learned the first time it is picked up
## — off an enemy's drop or out of the starter hand. An entry is one spell FILE: every tier under
## characters/player/spells/<spell>/ is an item of its own with its own icon (pew1, pew2,
## blam3_insect, nope), keyed by its basename. So the book needs no registration: a shipped spell
## file is an entry.

const SPELLS_ROOT := "res://characters/player/spells/"

## Its own save file, like the bestiary's: learned spells persist across new games and death, so
## they can't live in a file that GameState.clear_save() deletes.
const SAVE_PATH := "user://grimoire.cfg"

# entry id -> true. An entry is learned iff it has a key here.
var _learned: Dictionary = {}
var _entries: Array[StringName] = []
var _paths: Dictionary = {}  # entry id -> resource path

func _ready() -> void:
	_scan()
	_load()
	GlobalEvent.item_picked_up.connect(_on_item_picked_up)

## Every entry in book order: spells alphabetically by folder, each spell's files in tier order
## with a side tier after the tier it copies (pew1, pew2, pew3, pew3_insect).
func entries() -> Array[StringName]:
	return _entries

func load_spell(id: StringName) -> SpellResource:
	return load(_paths[id]) as SpellResource

func is_learned(id: StringName) -> bool:
	return _learned.has(id)

## How many of a set of entries are learned, as (learned, total) — pass entries() for the book.
func completion(ids: Array) -> Vector2i:
	var done := 0
	for id in ids:
		if _learned.has(id):
			done += 1
	return Vector2i(done, ids.size())

## The book's id for an item: its entry id when it is one of the shipped player spells, else &""
## (an enemy's bespoke cast, a minion's shot, a pathless debug spell).
func entry_id(item: ItemResource) -> StringName:
	if not item is SpellResource or item.resource_path.is_empty():
		return &""
	var id := StringName(item.resource_path.get_file().get_basename())
	return id if _paths.get(id, "") == item.resource_path else &""

## Save payload; the entries are re-derived from disk, only progress is serialized.
func to_dict() -> Dictionary:
	return {"learned": _learned.keys()}

func restore(dict: Dictionary) -> void:
	_learned.clear()
	for id in dict.get("learned", []):
		_learned[StringName(id)] = true

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("grimoire", "learned", to_dict()["learned"])
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	restore({"learned": cfg.get_value("grimoire", "learned", [])})

# A spell folder's own items are <spell>.tres (a spell with a single tier), <spell><n>.tres, or a
# side tier's <spell><n>_<kind>.tres. Everything else in there — a minion's shot (poot_shot),
# explosion frames (fireball_1_explosion), mine frames — is its effect's data, not an item, and the
# naming alone keeps it out. ResourceLoader.list_directory rather than DirAccess: an export remaps
# .tres files, and this lists them under their source names.
func _scan() -> void:
	_entries.clear()
	_paths.clear()
	var folders := Array(ResourceLoader.list_directory(SPELLS_ROOT)).filter(
			func(entry: String) -> bool: return entry.ends_with("/"))
	folders.sort()  # list_directory gives no order guarantee across platforms/exports
	for folder: String in folders:
		var pattern := RegEx.create_from_string(
				"^%s(?:(\\d+)(?:_([a-z]+))?)?\\.tres$" % folder.trim_suffix("/"))
		var found: Array = []  # [tier, kind, id]
		for file in ResourceLoader.list_directory(SPELLS_ROOT + folder):
			var m := pattern.search(file)
			if m == null:
				continue
			var id := StringName(file.get_basename())
			_paths[id] = SPELLS_ROOT + folder + file
			found.append([m.get_string(1).to_int(), m.get_string(2), id])
		# Tier order, then the base tier before the side tiers that copy it ("" sorts first).
		found.sort_custom(func(a: Array, b: Array) -> bool:
			return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
		for f in found:
			_entries.append(f[2])

func _on_item_picked_up(slot: GlobalInventory.Slot) -> void:
	if GameState.sandbox:
		return   # a tutorial pickup is not a discovery
	var id := entry_id(slot.item)
	if id == &"" or _learned.has(id):
		return
	_learned[id] = true
	_save()
	GlobalEvent.grimoire_entry_learned.emit(id)
