extends Node

## Bestiary progress tracker: kill counts per enemy type. Every page is in the book from
## the start; an individual entry unlocks the first time that enemy type is killed, so the
## page shows what is left to find. Enemy types are keyed by their folder id under
## characters/enemies/<id>/ — the same string id spawn tables use (SpawnTableEntry.enemy_id)
## — derived here from the CreatureResource's resource_path, so tracking needs no
## per-enemy registration: any enemy with an authored <id>_data.tres is trackable.

const ENEMIES_ROOT := "res://characters/enemies/"
const GEN_CONFIG_PATH := "res://world_content/gen_config.tres"

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

## The roster as display pages — one page per biome label, every one of them in the book from
## the start: each entry is `{biome, title, ids}` (`biome` is the page label, `title` what the
## book prints above it). Biomes wired into gen_config come first in world order, remaining
## labels alphabetically; inside a page commons sort alphabetically, rare enemies follow, the
## bosses close it. The bestiary panel renders one page per element; the debug console reads it
## to hand out a biome's whole drop pool.
func pages() -> Array:
	var out: Array = []
	for i in _groups.size():
		out.append(_page(i))
	return out

func _page(i: int) -> Dictionary:
	return {"biome": _group_biomes[i], "title": _group_titles[i], "ids": _groups[i]}

## The distinct enemies filed on any biome page — the encounterable roster the book measures
## whole-game completion against. An enemy with a data sheet but in no spawn table is unreachable,
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

# Bestiary membership is DERIVED, not stored: an enemy files onto a page because some room
# in that page's biome(s) spawns it. So the book always matches where enemies are actually
# met, a shared enemy files onto every page it appears in, and an enemy in no spawn table
# (unreachable) simply isn't in the book. Biomes sharing a BiomeDef.family merge into one
# page labelled with the family (sub-biome variants read as one chapter), titled by the first
# of them to author a BiomeDef.display_name.
# Ordering (commons alpha → rares → bosses) comes from CreatureResource.rarity.
# The book is GLOBAL: it walks every reachable config (see _all_configs), so a dungeon's
# floors file onto their biome's page exactly like an overworld biome's rooms do.
func _build_groups() -> void:
	_groups.clear()
	_group_biomes.clear()
	_group_titles.clear()
	var configs := _all_configs()
	var label_of: Dictionary = {}  # biome id -> page label (family when set)
	var title_of: Dictionary = {}  # page label -> authored title, first one wins
	for cfg in configs:
		for biome_def in cfg.biomes:
			var biome_label: StringName = biome_def.family if biome_def.family != &"" else biome_def.id
			label_of[biome_def.id] = biome_label
			if biome_def.display_name != "" and not title_of.has(biome_label):
				title_of[biome_label] = biome_def.display_name
	var by_label: Dictionary = {}  # page label -> Array of {id, rarity}
	var seen: Dictionary = {}      # "label|id" -> true, dedupe an enemy repeated across a page's rooms
	for cfg in configs:
		for rt in cfg.room_types:
			for biome in _room_type_biomes(rt):
				var label: StringName = label_of.get(biome, biome)
				for entry in rt.enemies:
					for id in _entry_enemy_ids(entry):
						if not _roster.has(id):
							continue  # only trackable enemies (those with a <id>_data.tres)
						var key := "%s|%s" % [label, id]
						if seen.has(key):
							continue
						seen[key] = true
						by_label.get_or_add(label, []).append({"id": id, "rarity": load_data(id).rarity})
	# Page order: biome order across the configs as walked (first appearance of each label), so
	# the overworld's pages come first and a dungeon's follow the door it hangs off. Then any
	# stragglers alphabetically (room types name registered biomes, so this is just
	# belt-and-braces).
	var label_order: Array = []
	for cfg in configs:
		for biome_def in cfg.biomes:
			var label: StringName = label_of[biome_def.id]
			if label not in label_order:
				label_order.append(label)
	var extra: Array = by_label.keys().filter(func(b: StringName) -> bool: return b not in label_order)
	extra.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for label in label_order + extra:
		if not by_label.has(label):
			continue
		var entries: Array = by_label[label]
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["rarity"] != b["rarity"]:
				return a["rarity"] < b["rarity"]
			return String(a["id"]) < String(b["id"]))
		var group: Array[StringName] = []
		for e in entries:
			group.append(e["id"])
		_groups.append(group)
		_group_biomes.append(label)
		# No authored name: the label capitalised, which already reads right for a biome whose
		# id is its name ("deepwood" -> "Deepwood").
		_group_titles.append(title_of.get(label, String(label).capitalize()))

## Every GenConfig whose rooms the player can reach, overworld first: the world's own, then each
## dungeon a door leads into, then that dungeon's per-floor configs — which is where a descent's
## enemies actually live, since a floor swaps the whole config. Walking the door link is what
## keeps the book global without a second registry to keep in sync: a dungeon wired up for the
## player is wired up for the bestiary.
func _all_configs() -> Array[GenConfig]:
	var out: Array[GenConfig] = []
	_collect_configs(load(GEN_CONFIG_PATH), out)
	return out

# Identity-deduped (load() hands back the same instance for a path), which also stops a pair of
# doors pointing at each other from recursing forever.
func _collect_configs(cfg: GenConfig, out: Array[GenConfig]) -> void:
	if cfg == null or out.has(cfg):
		return
	out.append(cfg)
	for floor_cfg in cfg.floor_configs:
		_collect_configs(floor_cfg, out)
	for rt in cfg.room_types:
		for feature in rt.features:
			var door := feature.data as DoorResource
			if door != null and door.target_scene != null:
				_collect_configs(_scene_config(door.target_scene), out)

# The GenConfig a dungeon scene's WorldStreamer carries, read off the packed scene state the same
# way idle_frames reads a creature's SpriteFrames — no instantiation, so building the book never
# spins up a dungeon. Null when the scene holds no config (an ordinary door's target).
func _scene_config(scene: PackedScene) -> GenConfig:
	var st := scene.get_state()
	for i in st.get_node_count():
		for p in st.get_node_property_count(i):
			if st.get_node_property_name(i, p) != &"config":
				continue
			var cfg := st.get_node_property_value(i, p) as GenConfig
			if cfg != null:
				return cfg
	return null

## Every enemy id a spawn-table entry can produce: a mixed pack lists them on its PackMembers
## (and its own enemy_id is unset), a single-type entry carries enemy_id directly.
func _entry_enemy_ids(entry: SpawnTableEntry) -> Array[StringName]:
	var out: Array[StringName] = []
	if not entry.members.is_empty():
		for m in entry.members:
			if not out.has(m.enemy_id):
				out.append(m.enemy_id)
	elif entry.enemy_id != &"":
		out.append(entry.enemy_id)
	return out

## The biome(s) a room type contributes its enemies to: its owning biome, or — for WORLD-unique
## rooms (which leave `biome` empty) — every biome they may be placed in.
func _room_type_biomes(rt: RoomTypeDef) -> Array:
	if rt.unique_scope == RoomTypeDef.UniqueScope.WORLD:
		return rt.unique_allowed_biomes
	if rt.biome != &"":
		return [rt.biome]
	return []

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
