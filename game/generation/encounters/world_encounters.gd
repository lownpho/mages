class_name WorldEncounters
extends RefCounted
## Deterministic encounters for a WorldGraph. Rooms build independently and lazily from their
## finished semantic interiors; asking in another order or after interior-cache eviction produces
## the same keys, composition and tiles. Decoration is never read.

## Every member of an encounter lies within this many tiles of its centre.
const MEMBER_SPREAD := 2.0
## Objects retain the same clear disc reserved by the interior. Warp arrivals get extra breathing
## room so the player never lands directly inside an encounter.
const OBJECT_CLEARANCE := RoomInterior.SITE_CLEAR
const LANDING_CLEARANCE := 6.0

var graph: WorldGraph
var interiors: WorldInteriors
## Encounter key -> encounter, populated as Rooms are requested.
var encounters: Dictionary[String, GeneratedEncounter] = {}
## Member persistence key -> member.
var members: Dictionary[String, EncounterMember] = {}

var _by_room: Dictionary[String, Array] = {}
var _room_bounds: Array[Rect2i] = []


func _init(world_graph: WorldGraph, world_interiors: WorldInteriors = null) -> void:
	graph = world_graph
	interiors = world_interiors if world_interiors != null else WorldInteriors.new(world_graph)
	for room in graph.room_list:
		var low := Vector2(INF, INF)
		var high := -low
		for point in room.polygon:
			low = low.min(point)
			high = high.max(point)
		var bounds := Rect2i(Vector2i(low.floor()), Vector2i((high - low).ceil()) + Vector2i.ONE)
		_room_bounds.append(bounds.grow(ceili(graph.warp_bound(bounds)) + 2))


## This Room's encounters, building them on first request.
func for_room(room: GeneratedRoom) -> Array[GeneratedEncounter]:
	if _by_room.has(room.key()):
		return _typed_encounters(_by_room[room.key()])
	var out: Array[GeneratedEncounter] = []
	match room.role:
		GeneratedRoom.Role.SPAWN, GeneratedRoom.Role.BREATHER:
			pass
		GeneratedRoom.Role.BOSS, GeneratedRoom.Role.MINIBOSS, GeneratedRoom.Role.RARE:
			out.append(_fixed(room))
		_:
			out = _ordinary(room)
	_by_room[room.key()] = out
	for encounter in out:
		encounters[encounter.key] = encounter
		for member in encounter.members:
			members[member.key] = member
	return out


## Builds every Room, requesting the given Rooms first. Building the shipped World this way costs
## every interior, so only generated-output tests use it; the game builds Rooms as they stream.
func generate_all(order: Array[GeneratedRoom] = []) -> void:
	for room in order:
		if room != null and graph.rooms.get(room.key()) == room:
			for_room(room)
	for room in graph.room_list:
		for_room(room)


func encounter_count(room: GeneratedRoom) -> int:
	return for_room(room).size()


## The Room's encounter count if something already built it, otherwise -1, without building.
func built_count(room: GeneratedRoom) -> int:
	return _by_room[room.key()].size() if _by_room.has(room.key()) else -1


## Every member whose tile lies in a streaming chunk. Rooms whose bounds touch the chunk generate
## on demand; filtering by the member tile makes each enemy belong to exactly one chunk.
func members_in_chunk(coord: Vector2i, chunk_tiles: int) -> Array[EncounterMember]:
	var rect := Rect2i(coord * chunk_tiles, Vector2i.ONE * chunk_tiles)
	var out: Array[EncounterMember] = []
	for room in graph.room_list:
		if not _room_bounds[room.index].intersects(rect):
			continue
		for encounter in for_room(room):
			for member in encounter.members:
				if rect.has_point(member.tile):
					out.append(member)
	return out


## FLOOR tiles owned by the Room, row-major. Density uses the size of this complete list before
## placement clearances are applied.
func walkable_tiles(room: GeneratedRoom) -> Array[Vector2i]:
	var interior := interiors.interior(room)
	var out: Array[Vector2i] = []
	for y in range(interior.rect.position.y, interior.rect.end.y):
		for x in range(interior.rect.position.x, interior.rect.end.x):
			var tile := Vector2i(x, y)
			if interior.class_at(tile) == WorldInteriors.FLOOR:
				out.append(tile)
	return out


func _ordinary(room: GeneratedRoom) -> Array[GeneratedEncounter]:
	var curve := graph.plan.content.curve
	var challenge := room.plan.challenge
	if room.role == GeneratedRoom.Role.TEACHING:
		challenge = maxi(0, challenge - curve.teach_dip)
	var floor := walkable_tiles(room)
	var expected := floor.size() * curve.encounter_density(challenge)
	var count := floori(expected)
	var fraction := expected - count
	if fraction > 0.0 and graph.plan.rng(WgHash.NS_ENCOUNTERS, "count/" + room.key()).randf() < fraction:
		count += 1

	var eligible: Array[CreatureResource] = []
	var eligible_fillers: Array[CreatureResource] = []
	for enemy in room.roster:
		if room.roster[enemy] > challenge or enemy == room.teaching:
			continue
		if room.fillers.has(enemy):
			eligible_fillers.append(enemy)
		else:
			eligible.append(enemy)
	_sort_enemies(eligible)
	_sort_enemies(eligible_fillers)
	# A Testing Room with no eligible content cannot make an empty fight. A Teaching Room's planned
	# enemy remains sufficient content even when its dip excludes everything else, and a small Room
	# whose dipped density rounds to nothing still holds the one introduction.
	if room.teaching == null and eligible.is_empty() and eligible_fillers.is_empty():
		count = 0
	elif room.teaching != null:
		count = maxi(count, 1)

	var candidates := _placement_candidates(room, floor)
	var used: Dictionary[Vector2i, bool] = {}
	var out: Array[GeneratedEncounter] = []
	for index in count:
		var encounter := GeneratedEncounter.new()
		encounter.key = "%s/encounter/%d" % [room.key(), index]
		encounter.room_key = room.key()
		encounter.challenge = challenge
		var rng := graph.plan.rng(WgHash.NS_ENCOUNTERS, encounter.key)
		var selected := _weighted_without_replacement(eligible, curve.encounter_types(challenge), rng)
		var groups: Array[Dictionary] = []
		if room.teaching != null:
			groups.append({"enemy": room.teaching, "teaching": true})
		for enemy in selected:
			groups.append({"enemy": enemy})
		for enemy in eligible_fillers:
			groups.append({"enemy": enemy, "filler": true})
		var composition: Array[Dictionary] = []
		for group in groups:
			var enemy: CreatureResource = group.enemy
			var group_rng := graph.plan.rng(WgHash.NS_MEMBERS, "%s/group/%s" % [encounter.key, _enemy_id(enemy)])
			var amount := group_rng.randi_range(enemy.group_min, enemy.group_max)
			for _member in amount:
				composition.append(group)
		_place(encounter, composition, candidates, used, false)
		out.append(encounter)
	return out


func _fixed(room: GeneratedRoom) -> GeneratedEncounter:
	var encounter := GeneratedEncounter.new()
	encounter.key = room.key() + "/encounter/0"
	encounter.room_key = room.key()
	encounter.challenge = room.plan.challenge
	encounter.fixed = true
	var authored := room.plan.encounter
	var composition: Array[Dictionary] = [{"enemy": authored.leader, "leader": true}]
	var escorts: Array[CreatureResource] = authored.escorts.keys()
	_sort_enemies(escorts)
	for enemy in escorts:
		for _member in authored.escorts[enemy]:
			composition.append({"enemy": enemy})
	var floor := walkable_tiles(room)
	_place(encounter, composition, _placement_candidates(room, floor), {}, authored.centred)
	return encounter


func _place(encounter: GeneratedEncounter, composition: Array[Dictionary], candidates: Array[Vector2i],
		used: Dictionary[Vector2i, bool], centred: bool) -> void:
	if composition.is_empty() or candidates.is_empty():
		return
	var free: Array[Vector2i] = []
	free.assign(candidates.filter(func(tile: Vector2i) -> bool: return not used.has(tile)))
	if free.is_empty():
		free = candidates
	var centre: Vector2i
	if centred:
		centre = _nearest(free, graph.tile_of(graph.rooms[encounter.room_key].seed))
	else:
		centre = free[graph.plan.rng(WgHash.NS_ENCOUNTERS, encounter.key + "/centre").randi_range(0, free.size() - 1)]
	encounter.centre = centre
	var close: Array[Vector2i] = []
	close.assign(candidates.filter(func(tile: Vector2i) -> bool:
		return Vector2(tile).distance_squared_to(Vector2(centre)) <= MEMBER_SPREAD * MEMBER_SPREAD))
	for index in composition.size():
		var fields: Dictionary = composition[index]
		var tile: Vector2i = centre
		if index > 0:
			var available: Array[Vector2i] = []
			available.assign(close.filter(func(candidate: Vector2i) -> bool: return not used.has(candidate)))
			if available.is_empty():
				available = close
			if not available.is_empty():
				var member_key := "%s/member/%d" % [encounter.key, index]
				var rng := graph.plan.rng(WgHash.NS_MEMBERS, member_key)
				tile = available[rng.randi_range(0, available.size() - 1)]
		var member := EncounterMember.new()
		member.key = "%s/member/%d" % [encounter.key, index]
		member.encounter_key = encounter.key
		member.room_key = encounter.room_key
		member.enemy = fields.enemy
		member.tile = tile
		member.leader = fields.get("leader", false)
		member.fixed = encounter.fixed
		member.filler = fields.get("filler", false)
		member.teaching = fields.get("teaching", false)
		encounter.members.append(member)
		used[tile] = true


func _placement_candidates(room: GeneratedRoom, floor: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for tile in floor:
		var clear := true
		for site in room.sites:
			var distance := LANDING_CLEARANCE if site.kind == ObjectSite.Kind.LANDING else OBJECT_CLEARANCE
			if Vector2(tile).distance_squared_to(Vector2(site.spot)) < distance * distance:
				clear = false
				break
		if clear:
			out.append(tile)
	# Content composition is stronger than a clearance preference. This fallback is only reachable
	# for a pathologically tiny authored Room, and remains deterministic.
	return out if not out.is_empty() else floor


static func _weighted_without_replacement(eligible: Array[CreatureResource], wanted: int,
		rng: RandomNumberGenerator) -> Array[CreatureResource]:
	var pool := eligible.duplicate()
	var out: Array[CreatureResource] = []
	for _pick in mini(wanted, pool.size()):
		var total := 0
		for enemy in pool:
			total += enemy.weight
		var roll := rng.randi_range(1, total)
		for index in pool.size():
			roll -= pool[index].weight
			if roll <= 0:
				out.append(pool[index])
				pool.remove_at(index)
				break
	return out


static func _nearest(candidates: Array[Vector2i], point: Vector2i) -> Vector2i:
	var best := candidates[0]
	var distance := best.distance_squared_to(point)
	for tile in candidates:
		var next := tile.distance_squared_to(point)
		if next < distance:
			distance = next
			best = tile
	return best


static func _sort_enemies(enemies: Array[CreatureResource]) -> void:
	enemies.sort_custom(func(a: CreatureResource, b: CreatureResource) -> bool:
		return a.resource_path < b.resource_path)


static func _enemy_id(enemy: CreatureResource) -> String:
	return enemy.resource_path.get_base_dir().get_file()


static func _typed_encounters(source: Array) -> Array[GeneratedEncounter]:
	var out: Array[GeneratedEncounter] = []
	out.assign(source)
	return out
