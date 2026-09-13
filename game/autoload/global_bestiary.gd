extends Node

## Bestiary progress tracker: kill counts per enemy type. Every page is in the book from
## the start; an individual entry unlocks the first time that enemy type is killed, so the
## page shows what is left to find. Enemy types are keyed by their folder id under
## characters/enemies/<id>/ — derived here from the CreatureResource's resource_path, the same
## file World rosters and Fixed encounters reference, so tracking needs no
## per-enemy registration: any enemy with an authored <id>_data.tres is trackable.

const ENEMIES_ROOT := "res://characters/enemies/"
## The World content whose rosters and Fixed encounters file enemies onto pages.
const WORLD_CONTENT := "res://generation/world/"

## Its own save file, separate from GameState's run save: kill counts persist across new
## games and death, so they can't live in a file that GameState.clear_save() deletes.
const SAVE_PATH := "user://bestiary.cfg"

# enemy_id -> kill count. An id is unlocked iff it has a key here.
var _kills: Dictionary = {}
var _roster: Array[StringName] = []
var _groups: Array = []  # Array of Array[StringName], one per page, display-ordered
var _group_biomes: Array[StringName] = []  # page label of each group, same order
var _group_titles: Array[String] = []  # display title of each group, same order

func _ready() -> void:
	_scan_roster()
	_build_groups()
	_load()
	GlobalEvent.creature_died.connect(_on_creature_died)

## Every trackable enemy id, alphabetical. An enemy folder is trackable when it carries
## a <id>_data.tres stat sheet — behaviours/ and the debug placeholder don't, so they
## fall out naturally.
func roster() -> Array[StringName]:
	return _roster

## The roster as display pages — one page per Biome, every one of them in the book from the
## start: each entry is `{biome, title, ids}` (`biome` is the Biome id, `title` what the book
## prints above it). Pages follow the Ideal path, then the Side biomes; inside a page commons sort
## alphabetically, rare enemies follow, the bosses close it. The bestiary panel renders one page
## per element; the debug console reads it to hand out a biome's whole drop pool.
func pages() -> Array:
	var out: Array = []
	for i in _groups.size():
		out.append(_page(i))
	return out

func _page(i: int) -> Dictionary:
	return {"biome": _group_biomes[i], "title": _group_titles[i], "ids": _groups[i]}

## The distinct enemies filed on any biome page — the encounterable roster the book measures
## whole-game completion against. An enemy with a data sheet but in no roster is unreachable,
## so it isn't counted; a shared enemy counts once.
func filed_ids() -> Array[StringName]:
	var seen: Dictionary = {}
	var out: Array[StringName] = []
	for g in _groups:
		for id in g:
			if not seen.has(id):
				seen[id] = true
				out.append(id)
	return out

## How many of a set of enemy ids are unlocked, as (killed, total) — the completion metric
## the book shows per biome page (pass a page's ids) and for the whole game (pass filed_ids()).
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
	return {"kills": _kills.duplicate()}

func restore(dict: Dictionary) -> void:
	_kills = dict.get("kills", {}).duplicate()

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("bestiary", "kills", _kills)
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	restore({"kills": cfg.get_value("bestiary", "kills", {})})

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

# Bestiary membership is DERIVED, not stored: an enemy files onto a Biome's page because the Biome's
# shared roster, one of its Zones' additive rosters, or one of its Fixed encounters (Boss, Miniboss,
# Rare, leader or escort) fields it. So the book always matches where enemies are actually met, a
# shared enemy files onto every page it appears in, and an enemy in no roster (unreachable) simply
# isn't in the book. Ordering (commons alpha → rares → bosses) comes from CreatureResource.rarity.
# The content is read directly rather than through ContentLoader: the book needs no validation
# report, and the files are the same ones the World loads.
func _build_groups() -> void:
	_groups.clear()
	_group_biomes.clear()
	_group_titles.clear()
	var world := load(WORLD_CONTENT + "world.tres") as WorldResource
	if world == null:
		return
	var biomes: Array[BiomeResource] = world.ideal_path.duplicate()
	for side in world.side_biomes:
		biomes.append(side.biome)
	for biome in biomes:
		if biome == null:
			continue
		var enemies: Dictionary[CreatureResource, bool] = {}
		_file_biome_enemies(biome.roster.keys(), [biome.boss], enemies)
		var zones_dir := biome.resource_path.get_base_dir() + "/zones/"
		for entry in ResourceLoader.list_directory(zones_dir):
			var zone := load(zones_dir + entry) as ZoneResource if entry.ends_with(".tres") else null
			if zone != null:
				_file_biome_enemies(zone.roster.keys(), zone.minibosses + zone.rares, enemies)
		var entries: Array = []
		for enemy in enemies:
			var id := _id_for(enemy)
			if _roster.has(id):
				entries.append({"id": id, "rarity": enemy.rarity})
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["rarity"] != b["rarity"]:
				return a["rarity"] < b["rarity"]
			return String(a["id"]) < String(b["id"]))
		if entries.is_empty():
			continue
		var group: Array[StringName] = []
		for e in entries:
			group.append(e["id"])
		var biome_id := StringName(biome.resource_path.get_base_dir().get_file())
		_groups.append(group)
		_group_biomes.append(biome_id)
		# The id capitalised reads right for a Biome whose id is its name ("deepwood" -> "Deepwood").
		_group_titles.append(String(biome_id).capitalize())

func _file_biome_enemies(roster: Array, fixed: Array, out: Dictionary[CreatureResource, bool]) -> void:
	for enemy: CreatureResource in roster:
		out[enemy] = true
	for encounter: FixedEncounterResource in fixed:
		if encounter == null:
			continue
		if encounter.leader != null:
			out[encounter.leader] = true
		for escort: CreatureResource in encounter.escorts:
			out[escort] = true

func _on_creature_died(data: CreatureResource, _position: Vector2) -> void:
	if GameState.sandbox:
		return   # a tutorial kill is not a discovery
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
