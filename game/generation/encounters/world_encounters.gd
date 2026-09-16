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
## When walls or other enemies fill a pack's disc, its members may reach this many times as far. Wall
## clearance leaves a crowded Room fewer tiles to spread over, so the reach has to allow for it.
const PACK_STRETCH := 3.0
## Random free tiles tried as each ordinary encounter's centre. The one farthest from the Room's
## earlier centres wins, so encounters spread over the Room instead of landing on each other.
const CENTRE_TRIES := 8
## Random draws for a free tile before searching the whole floor.
const FREE_TRIES := 16
## Objects retain the same clear disc reserved by the interior. Warp arrivals get extra breathing
## room so the player never lands directly inside an encounter.
const OBJECT_CLEARANCE := RoomInterior.SITE_CLEAR
const LANDING_CLEARANCE := 6.0
## Enemies keep this far, in tiles, from anything that isn't their own Room's floor, so they stand
## inside the Room instead of embedded in its walls, its rocks or a Passage's mouth.
const WALL_CLEARANCE := 3.0
## A Room whose clearance leaves it less than this share of its floor relaxes the clearance by a
## step, down to the least one, rather than crowd its enemies into the few tiles that pass.
const CLEARANCE_SHARE := 0.5
const CLEARANCE_STEP := 0.5
const CLEARANCE_MIN := 1.5
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

	## How many free tiles lie within radius of centre.
	func free_count(centre: Vector2i, radius: float) -> int:
		var reach := ceili(radius)
		var count := 0
		for y in range(-reach, reach + 1):
			for x in range(-reach, reach + 1):
				if x * x + y * y <= radius * radius and is_free(centre + Vector2i(x, y)):
					count += 1
		return count


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
	var radius := PACK_SPREAD * sqrt(composition.size())
	var centre := _centre(encounter, placement, centres, centred, radius, composition.size())
	encounter.centre = centre
	centres.append(centre)
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
				tile = placement.nearest(centre, placement.is_free)
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
func _centre(encounter: GeneratedEncounter, placement: Placement, centres: Array[Vector2i], centred: bool,
		radius: float, needed: int) -> Vector2i:
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
	var best_fits := false
	for _try in CENTRE_TRIES:
		var tile := placement.random_free(rng)
		if tile == NO_TILE:
			break
		var distance := 1 << 30
		for other in centres:
			distance = mini(distance, tile.distance_squared_to(other))
		# A centre with room for the whole pack beats one that would push its members out past the
		# Room's open floor; between two of a kind, the farthest from the earlier centres wins.
		var fits := placement.free_count(tile, radius) >= needed
		if best == NO_TILE or (fits and not best_fits) or (fits == best_fits and distance > best_distance):
			best_fits = fits
			best_distance = distance
			best = tile
	if best != NO_TILE:
		return best
	var untaken := placement.tiles.filter(func(tile: Vector2i) -> bool: return not placement.is_taken(tile))
	var pool := untaken if not untaken.is_empty() else placement.tiles
	return pool[rng.randi_range(0, pool.size() - 1)]


func _placement_candidates(room: GeneratedRoom, floor_tiles: Array[Vector2i]) -> Array[Vector2i]:
	var interior := interiors.interior(room)
	var off_sites: Array[Vector2i] = []
	var reaches := PackedInt32Array()
	for tile in floor_tiles:
		var clear := true
		for site in room.sites:
			var distance := LANDING_CLEARANCE if site.kind == ObjectSite.Kind.LANDING else OBJECT_CLEARANCE
			if Vector2(tile).distance_squared_to(Vector2(site.spot)) < distance * distance:
				clear = false
				break
		if not clear:
			continue
		off_sites.append(tile)
		reaches.append(_wall_reach(interior, tile))
	# Content composition is stronger than a clearance preference, so a Room too narrow or too rocky
	# to leave CLEARANCE_SHARE of its floor clear relaxes the clearance a step at a time. Failing
	# that it keeps whatever the least clearance leaves it, which is still off the walls, and only a
	# Room with no such tile at all places its enemies anywhere on its floor. Every step stays
	# deterministic.
	var clearance := WALL_CLEARANCE
	var relaxed: Array[Vector2i] = []
	while clearance >= CLEARANCE_MIN:
		var out: Array[Vector2i] = []
		for index in off_sites.size():
			if reaches[index] > clearance * clearance:
				out.append(off_sites[index])
		if not out.is_empty():
			if out.size() >= off_sites.size() * CLEARANCE_SHARE:
				return _with_hub(room, off_sites, out)
			relaxed = out
		clearance -= CLEARANCE_STEP
	if not relaxed.is_empty():
		return _with_hub(room, off_sites, relaxed)
	return off_sites if not off_sites.is_empty() else floor_tiles


## Keeps the Room's centre placeable when it clears the Object sites: its own clear disc is smaller
## than WALL_CLEARANCE, so a strict clearance would otherwise push a centred set piece's leader off
## the seed tile it is authored on.
func _with_hub(room: GeneratedRoom, off_sites: Array[Vector2i], pool: Array[Vector2i]) -> Array[Vector2i]:
	var hub := graph.tile_of(room.seed_point)
	if off_sites.has(hub) and not pool.has(hub):
		pool.append(hub)
	return pool


## The squared distance from a tile to the nearest tile within WALL_CLEARANCE that is not this same
## Room's floor, or just past that reach when they all are. Another Room's tiles read as OUTSIDE
## here, so a Passage's mouth is no more placeable than a wall.
func _wall_reach(interior: RoomInterior, tile: Vector2i) -> int:
	var reach := ceili(WALL_CLEARANCE)
	var nearest := reach * reach + 1
	for y in range(-reach, reach + 1):
		for x in range(-reach, reach + 1):
			var distance := x * x + y * y
			if distance >= nearest:
				continue
			if interior.class_at(tile + Vector2i(x, y)) != WorldInteriors.FLOOR:
				nearest = distance
	return nearest


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
