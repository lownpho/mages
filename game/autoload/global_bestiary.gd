extends Node

## Bestiary progress tracker: kill counts per enemy type. An entry unlocks the first
## time that enemy type is killed. Enemy types are keyed by their folder id under
## characters/enemies/<id>/ — the same string id spawn tables use (SpawnTableEntry.enemy_id)
## — derived here from the CreatureResource's resource_path, so tracking needs no
## per-enemy registration: any enemy with an authored <id>_data.tres is trackable.

const ENEMIES_ROOT := "res://characters/enemies/"
const GEN_CONFIG_PATH := "res://world_content/gen_config.tres"

## Its own save file, separate from GameState's run save: kill counts and visited
## biomes persist across new games and death, so they can't live in a file that
## GameState.clear_save() deletes.
const SAVE_PATH := "user://bestiary.cfg"

# enemy_id -> kill count. An id is unlocked iff it has a key here.
var _kills: Dictionary = {}
# biome id -> true, for every biome the player has ever stepped into.
var _visited: Dictionary = {}
var _roster: Array[StringName] = []
var _groups: Array = []  # Array of Array[StringName], one per biome, display-ordered
var _group_biomes: Array[StringName] = []  # biome label of each group, same order
var _group_bosses: Array[StringName] = []  # the boss enemy id of each group (&"" if none), same order

func _ready() -> void:
	_scan_roster()
	_build_groups()
	_load()
	GlobalEvent.creature_died.connect(_on_creature_died)
	GlobalEvent.biome_entered.connect(_on_biome_entered)

## Every trackable enemy id, alphabetical. An enemy folder is trackable when it carries
## a <id>_data.tres stat sheet — behaviours/ and the debug placeholder don't, so they
## fall out naturally.
func roster() -> Array[StringName]:
	return _roster

## The roster grouped for display: one group per biome label. Biomes wired into
## gen_config come first in world order, remaining labels alphabetically; inside a
## group commons sort alphabetically, rare enemies follow, the boss closes the group.
func grouped_roster() -> Array:
	return _groups

## Only the groups the player has discovered: a section shows once its biome has been
## visited, or once any of its enemies is unlocked — the fallback covers labels that
## aren't walkable biomes (e.g. dungeon guards), which surface on first kill.
func visible_grouped_roster() -> Array:
	var out: Array = []
	for i in _groups.size():
		if _is_group_visible(i):
			out.append(_groups[i])
	return out

## Discovered biomes as display pages — one page per biome, richest form for the book UI:
## each entry is `{biome, boss, ids}` (ids commons→rares→boss; `boss` is the biome's boss
## enemy id or &"" if it has none), same order/visibility as visible_grouped_roster. The
## bestiary panel renders one page per element and badges it with the boss emblem.
func visible_pages() -> Array:
	var out: Array = []
	for i in _groups.size():
		if _is_group_visible(i):
			out.append({"biome": _group_biomes[i], "boss": _group_bosses[i], "ids": _groups[i]})
	return out

func _is_group_visible(i: int) -> bool:
	return _visited.has(_group_biomes[i]) \
		or _groups[i].any(func(id: StringName) -> bool: return _kills.has(id))

## How many of a set of enemy ids are unlocked, as (killed, total) — the completion metric
## the book shows per biome page (pass a page's ids) and for the whole game (pass roster()).
func completion(ids: Array) -> Vector2i:
	var done := 0
	for id in ids:
		if _kills.has(id):
			done += 1
	return Vector2i(done, ids.size())

func load_data(enemy_id: StringName) -> CreatureResource:
	return load(_data_path(enemy_id)) as CreatureResource

## The enemy's embedded idle SpriteFrames, read straight off its scene's AnimatedSprite2D via
## the packed scene state — no instantiation, so the bestiary never spins up a live creature
## just to animate a thumbnail. Null if the scene or an AnimatedSprite2D isn't found.
func idle_frames(enemy_id: StringName) -> SpriteFrames:
	var path := _scene_path(enemy_id)
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var st := ps.get_state()
	for i in st.get_node_count():
		if st.get_node_type(i) != &"AnimatedSprite2D":
			continue
		for p in st.get_node_property_count(i):
			if st.get_node_property_name(i, p) == &"sprite_frames":
				return st.get_node_property_value(i, p) as SpriteFrames
	return null

func kill_count(enemy_id: StringName) -> int:
	return _kills.get(enemy_id, 0)

func is_unlocked(enemy_id: StringName) -> bool:
	return _kills.has(enemy_id)

## Save payload; the roster is re-derived from disk, only progress is serialized.
func to_dict() -> Dictionary:
	return {"kills": _kills.duplicate(), "visited": _visited.duplicate()}

func restore(dict: Dictionary) -> void:
	_kills = dict.get("kills", {}).duplicate()
	_visited = dict.get("visited", {}).duplicate()

func _save() -> void:
	var cfg := ConfigFile.new()
	var data := to_dict()
	cfg.set_value("bestiary", "kills", data["kills"])
	cfg.set_value("bestiary", "visited", data["visited"])
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	restore({
		"kills": cfg.get_value("bestiary", "kills", {}),
		"visited": cfg.get_value("bestiary", "visited", {}),
	})

func _data_path(enemy_id: StringName) -> String:
	return ENEMIES_ROOT + "%s/%s_data.tres" % [enemy_id, enemy_id]

func _scene_path(enemy_id: StringName) -> String:
	return ENEMIES_ROOT + "%s/%s.tscn" % [enemy_id, enemy_id]

func _scan_roster() -> void:
	_roster.clear()
	for dir in DirAccess.get_directories_at(ENEMIES_ROOT):
		var id := StringName(dir)
		if ResourceLoader.exists(_data_path(id)):
			_roster.append(id)
	# get_directories_at gives no order guarantee across platforms/exports.
	_roster.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))

func _on_biome_entered(biome_id: StringName) -> void:
	if _visited.has(biome_id):
		return
	_visited[biome_id] = true
	_save()

func _build_groups() -> void:
	_groups.clear()
	_group_biomes.clear()
	_group_bosses.clear()
	var by_biome: Dictionary = {}  # biome StringName -> Array of {id, rarity}
	for id in _roster:
		var data := load_data(id)
		by_biome.get_or_add(data.biome, []).append({"id": id, "rarity": data.rarity})
	var biome_order: Array = []
	var cfg: GenConfig = load(GEN_CONFIG_PATH)
	for biome_def in cfg.biomes:
		biome_order.append(biome_def.id)
	var unwired: Array = by_biome.keys().filter(func(b: StringName) -> bool: return b not in biome_order)
	unwired.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for biome in biome_order + unwired:
		if not by_biome.has(biome):
			continue
		var entries: Array = by_biome[biome]
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["rarity"] != b["rarity"]:
				return a["rarity"] < b["rarity"]
			return String(a["id"]) < String(b["id"]))
		var group: Array[StringName] = []
		var boss: StringName = &""
		for e in entries:
			group.append(e["id"])
			if e["rarity"] == CreatureResource.Rarity.BOSS:
				boss = e["id"]
		_groups.append(group)
		_group_biomes.append(biome)
		_group_bosses.append(boss)

func _on_creature_died(data: CreatureResource, _position: Vector2) -> void:
	var id := _id_for(data)
	if id == &"" or not _roster.has(id):
		return
	var first: bool = not _kills.has(id)
	_kills[id] = _kills.get(id, 0) + 1
	_save()
	if first:
		GlobalEvent.bestiary_entry_unlocked.emit(id)
	GlobalEvent.bestiary_updated.emit(id, _kills[id])

# "res://characters/enemies/owl/owl_data.tres" -> &"owl". A summon's injected stats
# have no resource_path, so they yield &"" and are ignored.
func _id_for(data: CreatureResource) -> StringName:
	if data == null or data.resource_path.is_empty():
		return &""
	return StringName(data.resource_path.get_base_dir().get_file())
