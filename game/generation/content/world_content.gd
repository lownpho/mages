class_name WorldContent
extends RefCounted
## The content of one World as ContentLoader.load_content found it, with every problem the load pass
## reported. Ids are folder and file names. Zone counts and Room totals are derived from the Zone
## files and their quotas; nothing authors them separately.

## A Side biome attaches to an Ideal-path route Room at least this many route Rooms from its parent's
## entrance and exit...
const ATTACHMENT_MARGIN := 2
## ...and at least this many route Rooms from its parent's other Side-biome attachments.
const ATTACHMENT_SPACING := 3

## The content folder, ending in "/".
var root := ""
var errors: Array[ContentError] = []
var world: WorldResource
var curve: ChallengeCurveResource
## Biome id -> Biome, for every Biome folder whose biome.tres loaded, in id order.
var biomes: Dictionary[StringName, BiomeResource] = {}
## Biome id -> {Zone id -> ZoneResource}, for the Zone files that loaded, in id order.
var zones: Dictionary[StringName, Dictionary] = {}
## Biome ids on the Ideal path, in order.
var ideal_path: Array[StringName] = []
## Side biome id -> parent Biome id, in world.tres order.
var parents: Dictionary[StringName, StringName] = {}
## "biome/zone", once exactly one Zone is the Spawn zone.
var spawn_zone := ""


func is_valid() -> bool:
	return errors.is_empty()


## Every problem, one "path:line: message" per line.
func report() -> String:
	return "\n".join(errors.map(func(error: ContentError) -> String: return str(error)))


## The Ideal path's Biomes, then the Side biomes.
func biome_ids() -> Array[StringName]:
	var out := ideal_path.duplicate()
	out.append_array(parents.keys())
	return out


func is_side_biome(biome_id: StringName) -> bool:
	return parents.has(biome_id)


## The lowest Challenge on a Biome's route: where an Ideal-path Biome starts (the previous Biome's
## exit), or for a Side biome, where its parent starts, since it may attach anywhere on that route.
func lowest_challenge(biome_id: StringName) -> int:
	if parents.has(biome_id):
		return lowest_challenge(parents[biome_id])
	var index := ideal_path.find(biome_id)
	return 0 if index <= 0 else biomes[ideal_path[index - 1]].exit_challenge


## Every enemy filed onto a Biome's Bestiary page, each once, in content order: its shared roster,
## its Zones' additive rosters and every Fixed encounter it fields (its Boss, its Zones' Minibosses
## and Rares, leaders and escorts alike). This is the rule the Bestiary files pages by, so a
## Professor measuring a Biome page against it measures exactly what the book shows.
func biome_enemies(biome_id: StringName) -> Array[CreatureResource]:
	var out: Array[CreatureResource] = []
	var biome: BiomeResource = biomes.get(biome_id)
	if biome == null:
		return out
	_file_enemies(biome.roster.keys(), [biome.boss], out)
	for zone: ZoneResource in zones.get(biome_id, {}).values():
		_file_enemies(zone.roster.keys(), zone.minibosses + zone.rares, out)
	return out


func _file_enemies(roster: Array, fixed: Array, out: Array[CreatureResource]) -> void:
	for creature: CreatureResource in roster:
		if creature != null and not out.has(creature):
			out.append(creature)
	for encounter: FixedEncounterResource in fixed:
		if encounter == null:
			continue
		if encounter.leader != null and not out.has(encounter.leader):
			out.append(encounter.leader)
		for escort: CreatureResource in encounter.escorts:
			if escort != null and not out.has(escort):
				out.append(escort)


func zone_ids(biome_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(zones.get(biome_id, {}).keys())
	return out


func zone_count(biome_id: StringName) -> int:
	return zones.get(biome_id, {}).size()


## Rooms on the Biome's Ideal-path stretch or Side route: the sum of its Zones' route_rooms.
func route_rooms(biome_id: StringName) -> int:
	var total := 0
	for zone: ZoneResource in zones.get(biome_id, {}).values():
		total += zone.route_rooms
	return total


## Every Room of the Biome: the sum of its Zones' room_count.
func room_count(biome_id: StringName) -> int:
	var total := 0
	for zone: ZoneResource in zones.get(biome_id, {}).values():
		total += zone.room_count
	return total


func world_room_count() -> int:
	var total := 0
	for biome_id in zones:
		total += room_count(biome_id)
	return total
