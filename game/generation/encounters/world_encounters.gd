class_name WorldEncounters
extends RefCounted
## Deterministic encounters and Hazards for a WorldGraph. Rooms build independently and lazily from
## their finished semantic interiors; asking in another order or after interior-cache eviction
## produces the same keys, composition and tiles. Decoration is never read.
##
## No two generated enemies of a Room share or touch a tile. Ordinary encounters spread over the
## Room, each a loose pack around its centre; Hazards then scatter over whatever floor is left.

## A pack's members lie within this many tiles of its centre per square root of its size, which
## leaves room for a free tile between neighbours.
const PACK_SPREAD := 1.6
## When walls or other enemies fill a pack's disc, its members may reach this many times as far.
const PACK_STRETCH := 2.0
## Random free tiles tried as each ordinary encounter's centre. The one farthest from the Room's
## earlier centres wins, so encounters spread over the Room instead of landing on each other.
const CENTRE_TRIES := 8
## Random draws for a free tile before searching the whole floor.
const FREE_TRIES := 16
## Objects retain the same clear disc reserved by the interior. Warp arrivals get extra breathing
## room so the player never lands directly inside an encounter.
const OBJECT_CLEARANCE := RoomInterior.SITE_CLEAR
const LANDING_CLEARANCE := 6.0
const NO_TILE := Vector2i(-1073741824, -1073741824)

var graph: WorldGraph
var interiors: WorldInteriors
## Encounter key -> encounter, populated as Rooms are requested.
var encounters: Dictionary[String, GeneratedEncounter] = {}
## Member persistence key -> member, Hazards included.
var members: Dictionary[String, EncounterMember] = {}

var _by_room: Dictionary[String, Array] = {}
var _hazards_by_room: Dictionary[String, Array] = {}
var _room_bounds: Array[Rect2i] = []


## The floor a Room's enemies are placed on, and the tiles they already take or touch.
class Placement:
	var tiles: Array[Vector2i] = []
	var _placeable: Dictionary[Vector2i, bool] = {}
	var _taken: Dictionary[Vector2i, bool] = {}
	## Taken tiles and their eight neighbours.
	var _blocked: Dictionary[Vector2i, bool] = {}

	func _init(candidates: Array[Vector2i]) -> void:
		tiles = candidates
		for tile in candidates:
			_placeable[tile] = true

	func is_free(tile: Vector2i) -> bool:
		return _placeable.has(tile) and not _blocked.has(tile)

	func is_taken(tile: Vector2i) -> bool:
		return _taken.has(tile)

	func claim(tile: Vector2i) -> void:
		_taken[tile] = true
		for y in range(-1, 2):
			for x in range(-1, 2):
				_blocked[tile + Vector2i(x, y)] = true

	## A random free tile, trying a few draws before searching the whole floor; NO_TILE when none is.
	func random_free(rng: RandomNumberGenerator) -> Vector2i:
		for _try in FREE_TRIES:
			var tile := tiles[rng.randi_range(0, tiles.size() - 1)]
			if is_free(tile):
				return tile
		var free := tiles.filter(is_free)
		return free[rng.randi_range(0, free.size() - 1)] if not free.is_empty() else NO_TILE

	## A random free tile within radius of centre, NO_TILE when none is.
	func free_near(centre: Vector2i, radius: float, rng: RandomNumberGenerator) -> Vector2i:
		var reach := ceili(radius)
		var near: Array[Vector2i] = []
		for y in range(-reach, reach + 1):
			for x in range(-reach, reach + 1):
				var tile := centre + Vector2i(x, y)
				if x * x + y * y <= radius * radius and is_free(tile):
					near.append(tile)
		return near[rng.randi_range(0, near.size() - 1)] if not near.is_empty() else NO_TILE

	## The nearest tile passing accept, NO_TILE when none does.
	func nearest(point: Vector2i, accept: Callable) -> Vector2i:
		var best := NO_TILE
		var distance := 0
		for tile in tiles:
			if not accept.call(tile):
				continue
			var next := tile.distance_squared_to(point)
			if best == NO_TILE or next < distance:
				distance = next
				best = tile
		return best


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


## This Room's encounters, building the Room on first request.
func for_room(room: GeneratedRoom) -> Array[GeneratedEncounter]:
	_build(room)
	var out: Array[GeneratedEncounter] = []
	out.assign(_by_room[room.key()])
	return out


## This Room's Hazards, building the Room on first request.
func hazards_for_room(room: GeneratedRoom) -> Array[EncounterMember]:
	_build(room)
	var out: Array[EncounterMember] = []
	out.assign(_hazards_by_room[room.key()])
	return out


## Builds every Room, requesting the given Rooms first. Building the shipped World this way costs
## every interior, so only generated-output tests use it; the game builds Rooms as they stream.
func generate_all(order: Array[GeneratedRoom] = []) -> void:
	for room in order:
		if room != null and graph.rooms.get(room.key()) == room:
			_build(room)
	for room in graph.room_list:
		_build(room)


func encounter_count(room: GeneratedRoom) -> int:
	return for_room(room).size()


## The Room's encounter count if something already built it, otherwise -1, without building.
func built_count(room: GeneratedRoom) -> int:
	return _by_room[room.key()].size() if _by_room.has(room.key()) else -1


## Every member and Hazard whose tile lies in a streaming chunk. Rooms whose bounds touch the chunk
## generate on demand; filtering by the member tile makes each enemy belong to exactly one chunk.
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
		for member: EncounterMember in _hazards_by_room[room.key()]:
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


func _build(room: GeneratedRoom) -> void:
	if _by_room.has(room.key()):
		return
	var out: Array[GeneratedEncounter] = []
	var room_hazards: Array[EncounterMember] = []
	match room.role:
		GeneratedRoom.Role.SPAWN, GeneratedRoom.Role.BREATHER:
			pass
		GeneratedRoom.Role.BOSS, GeneratedRoom.Role.MINIBOSS, GeneratedRoom.Role.RARE:
			out.append(_fixed(room))
		_:
			var floor_tiles := walkable_tiles(room)
			var placement := Placement.new(_placement_candidates(room, floor_tiles))
			out = _ordinary(room, floor_tiles.size(), placement)
			room_hazards = _hazards(room, floor_tiles.size(), placement)
	_by_room[room.key()] = out
	_hazards_by_room[room.key()] = room_hazards
	for encounter in out:
		encounters[encounter.key] = encounter
		for member in encounter.members:
			members[member.key] = member
	for member in room_hazards:
		members[member.key] = member


func _ordinary(room: GeneratedRoom, floor_size: int, placement: Placement) -> Array[GeneratedEncounter]:
	var curve := graph.plan.content.curve
	var challenge := room.plan.challenge
	if room.role == GeneratedRoom.Role.TEACHING:
		challenge = maxi(0, challenge - curve.teach_dip)
	var expected := floor_size * curve.encounter_density(challenge)
	var count := floori(expected)
	var fraction := expected - count
	if fraction > 0.0 and graph.plan.rng(WorldHash.NS_ENCOUNTERS, "count/" + room.key()).randf() < fraction:
		count += 1

	var eligible: Array[CreatureResource] = []
	for enemy in room.roster:
		if room.roster[enemy] <= challenge and enemy != room.teaching and not enemy.is_hazard():
			eligible.append(enemy)
	_sort_enemies(eligible)
	# A Testing Room with no eligible content cannot make an empty fight. A Teaching Room's planned
	# enemy remains sufficient content even when its dip excludes everything else, and a small Room
	# whose dipped density rounds to nothing still holds the one introduction.
	if room.teaching == null and eligible.is_empty():
		count = 0
	elif room.teaching != null:
		count = maxi(count, 1)

	var centres: Array[Vector2i] = []
	var out: Array[GeneratedEncounter] = []
	for index in count:
		var encounter := GeneratedEncounter.new()
		encounter.key = "%s/encounter/%d" % [room.key(), index]
		encounter.room_key = room.key()
		encounter.challenge = challenge
		var rng := graph.plan.rng(WorldHash.NS_ENCOUNTERS, encounter.key)
		var selected := _weighted_without_replacement(eligible, curve.encounter_types(challenge), rng)
		var groups: Array[Dictionary] = []
		if room.teaching != null:
			groups.append({"enemy": room.teaching, "teaching": true})
		for enemy in selected:
			groups.append({"enemy": enemy})
		var composition: Array[Dictionary] = []
		for group in groups:
			var enemy: CreatureResource = group.enemy
			var group_rng := graph.plan.rng(WorldHash.NS_MEMBERS, "%s/group/%s" % [encounter.key, _enemy_id(enemy)])
			var amount := group_rng.randi_range(enemy.group_min, enemy.group_max)
			for _member in amount:
				composition.append(group)
		_place(encounter, composition, placement, centres, false)
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
	var placement := Placement.new(_placement_candidates(room, walkable_tiles(room)))
	_place(encounter, composition, placement, [], authored.centred)
	return encounter


## Every eligible Hazard at its own density over the Room's floor, at the Room's own Challenge.
## A Hazard that finds no free tile left is dropped rather than made to touch another enemy.
func _hazards(room: GeneratedRoom, floor_size: int, placement: Placement) -> Array[EncounterMember]:
	var eligible: Array[CreatureResource] = []
	for enemy in room.roster:
		if enemy.is_hazard() and room.roster[enemy] <= room.plan.challenge:
			eligible.append(enemy)
	_sort_enemies(eligible)
	var out: Array[EncounterMember] = []
	for enemy in eligible:
		var key := "%s/hazard/%s" % [room.key(), _enemy_id(enemy)]
		var rng := graph.plan.rng(WorldHash.NS_MEMBERS, key)
		var expected := floor_size * enemy.hazards_per_tile
		var count := floori(expected)
		if rng.randf() < expected - count:
			count += 1
		for index in count:
			if placement.tiles.is_empty():
				break
			var tile := placement.random_free(rng)
			if tile == NO_TILE:
				break
			placement.claim(tile)
			var member := EncounterMember.new()
			member.key = "%s/%d" % [key, index]
			member.room_key = room.key()
			member.enemy = enemy
			member.tile = tile
			member.hazard = true
			out.append(member)
	return out


func _place(encounter: GeneratedEncounter, composition: Array[Dictionary], placement: Placement,
		centres: Array[Vector2i], centred: bool) -> void:
	if composition.is_empty() or placement.tiles.is_empty():
		return
	var centre := _centre(encounter, placement, centres, centred)
	encounter.centre = centre
	centres.append(centre)
	var radius := PACK_SPREAD * sqrt(composition.size())
	for index in composition.size():
		var fields: Dictionary = composition[index]
		var member_key := "%s/member/%d" % [encounter.key, index]
		var tile := centre
		if index > 0:
			var rng := graph.plan.rng(WorldHash.NS_MEMBERS, member_key)
			tile = placement.free_near(centre, radius, rng)
			if tile == NO_TILE:
				tile = placement.free_near(centre, radius * PACK_STRETCH, rng)
			if tile == NO_TILE:
				tile = placement.nearest(centre, func(candidate: Vector2i) -> bool: return not placement.is_taken(candidate))
			if tile == NO_TILE:
				tile = centre
		placement.claim(tile)
		var member := EncounterMember.new()
		member.key = member_key
		member.encounter_key = encounter.key
		member.room_key = encounter.room_key
		member.enemy = fields.enemy
		member.tile = tile
		member.leader = fields.get("leader", false)
		member.fixed = encounter.fixed
		member.teaching = fields.get("teaching", false)
		encounter.members.append(member)


## A centred encounter takes the free tile nearest the Room's seed. Otherwise the farthest from the
## Room's earlier centres among a few random free tiles. Crowded Rooms fall back to untaken tiles,
## then to any tile.
func _centre(encounter: GeneratedEncounter, placement: Placement, centres: Array[Vector2i], centred: bool) -> Vector2i:
	if centred:
		var seed_tile := graph.tile_of(graph.rooms[encounter.room_key].seed_point)
		for accept: Callable in [placement.is_free, func(tile: Vector2i) -> bool: return not placement.is_taken(tile),
				func(_tile: Vector2i) -> bool: return true]:
			var tile := placement.nearest(seed_tile, accept)
			if tile != NO_TILE:
				return tile
	var rng := graph.plan.rng(WorldHash.NS_ENCOUNTERS, encounter.key + "/centre")
	var best := NO_TILE
	var best_distance := -1
	for _try in CENTRE_TRIES:
		var tile := placement.random_free(rng)
		if tile == NO_TILE:
			break
		var distance := 1 << 30
		for other in centres:
			distance = mini(distance, tile.distance_squared_to(other))
		if distance > best_distance:
			best_distance = distance
			best = tile
	if best != NO_TILE:
		return best
	var untaken := placement.tiles.filter(func(tile: Vector2i) -> bool: return not placement.is_taken(tile))
	var pool := untaken if not untaken.is_empty() else placement.tiles
	return pool[rng.randi_range(0, pool.size() - 1)]


func _placement_candidates(room: GeneratedRoom, floor_tiles: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for tile in floor_tiles:
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
	return out if not out.is_empty() else floor_tiles


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


static func _sort_enemies(enemies: Array[CreatureResource]) -> void:
	enemies.sort_custom(func(a: CreatureResource, b: CreatureResource) -> bool:
		return a.resource_path < b.resource_path)


static func _enemy_id(enemy: CreatureResource) -> String:
	return enemy.resource_path.get_base_dir().get_file()
