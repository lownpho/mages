class_name SitePlanner
extends RefCounted
## Plans a WorldGraph's Object sites once Teaching rooms and chance Breathers are known.
##
## Every authored Sign stands once, in its Biome, or in its Zone when a Zone authors it; each Biome
## places its Professor and Warp-door counts. Those Rooms must not teach and become Breathers. Each
## door picks a seeded target Biome (an adjacent Ideal-path Biome, or a Side biome's parent) and a
## landing in an ordinary Room there that isn't a Breather; landings leave roles alone and may share
## a Room. Every choice takes the first candidate in seeded order at least two room sizes from the
## sites placed so far, or the farthest when none is. A spreading pass then moves each site still
## short of two room sizes to the candidate Room that keeps it farthest from the rest. The layout
## stands when every pair keeps MIN_SPACING of two room sizes. Signs reveal
## the nearest planned Boss their enemy leads. Chance Breathers left without sites draw one Object by
## weight from their Biome's and Zone's choices, or stay empty when they have none.
##
## Spots default to the Room's seed. When that would break spacing, placement searches deterministic
## interior points toward the Room's corners and edges; sites sharing a Room keep separate spots.

## Tiles between two sites sharing a Room.
const SHARED_ROOM_GAP := 6.0
## The least share of two room sizes every pair of spaced sites must keep. Placement still aims for
## the full two room sizes; near misses are accepted rather than failing the World.
const MIN_SPACING := 0.8
## Passes of the spreading step.
const SPREAD_PASSES := 4
## Only inverse-warp the most promising sampled points; ranking all of them in unwarped space is
## much cheaper and preserves the startup budget.
const SPOT_FINALISTS := 2

var graph: WorldGraph
var plan: WorldPlan
## Signs, Professors, doors and landings, as they are placed.
var _spaced: Array[ObjectSite] = []
## Site -> the Rooms it may stand in.
var _candidates: Dictionary[ObjectSite, Array] = {}
## Door -> its landing.
var _landings: Dictionary[ObjectSite, ObjectSite] = {}
## The Breathers the chance picked before any site forced one.
var _chance: Dictionary[GeneratedRoom, bool] = {}
var _seed_spots: Dictionary[GeneratedRoom, Vector2i] = {}


func _init(world_graph: WorldGraph) -> void:
	graph = world_graph
	plan = world_graph.plan
	for key in graph.rooms:
		if graph.rooms[key].role == GeneratedRoom.Role.BREATHER:
			_chance[graph.rooms[key]] = true


## Signs, Professors and Warp doors with their landings, spread apart, with Sign reveals. False means
## deterministic candidates were exhausted, which is a generation bug rather than a partial graph.
func place() -> bool:
	for id in plan.content.biome_ids():
		var biome := plan.biomes[id]
		for n in biome.resource.signs.size():
			_place_sign(biome, null, biome.resource.signs[n], "sign/%s/%d" % [id, n])
		for zone in biome.zones:
			for n in zone.resource.signs.size():
				_place_sign(biome, zone, zone.resource.signs[n], "sign/%s/%s/%d" % [id, zone.id, n])
		for n in biome.resource.professors:
			_place_forced(biome, null, ObjectSite.Kind.PROFESSOR, "professor/%s/%d" % [id, n])
		for n in biome.resource.warp_doors:
			var unit := "door/%s/%d" % [id, n]
			var door := _place_forced(biome, null, ObjectSite.Kind.DOOR, unit)
			if door == null:
				continue
			var targets := _door_targets(id)
			door.destination_biome = targets[plan.rng(WgHash.NS_SITES, unit).randi_range(0, targets.size() - 1)]
			_place_landing(door, "landing/" + unit)
	_spread()
	if not _layout_is_valid():
		push_error("World seed %d: Object-site placement exhausted before every site was spaced" % plan.world_seed)
		return false
	for site in _spaced:
		if site.kind == ObjectSite.Kind.SIGN:
			site.reveal_key = _nearest_boss(site)
	return true


func place_weighted() -> void:
	for key in graph.rooms:
		var room := graph.rooms[key]
		if room.role != GeneratedRoom.Role.BREATHER or not room.sites.is_empty():
			continue
		var weights: Dictionary[PackedScene, int] = plan.biomes[room.plan.biome].resource.breather_objects.duplicate()
		var zone := plan.biomes[room.plan.biome].zone(room.plan.zone)
		for scene in zone.resource.breather_objects:
			weights[scene] = weights.get(scene, 0) + zone.resource.breather_objects[scene]
		var scenes: Array[PackedScene] = weights.keys()
		scenes.sort_custom(func(a: PackedScene, b: PackedScene) -> bool: return a.resource_path < b.resource_path)
		var total := 0
		for scene in scenes:
			total += weights[scene]
		if total <= 0:
			continue
		var roll := plan.rng(WgHash.NS_SITES, "weighted/" + key).randi_range(1, total)
		for scene in scenes:
			roll -= weights[scene]
			if roll <= 0:
				var site := _add_site(room, ObjectSite.Kind.WEIGHTED, _free_spot(room))
				site.scene = scene
				break


## Two room sizes: the larger of the two Rooms' Biomes'.
func spacing(a: GeneratedRoom, b: GeneratedRoom) -> float:
	return 2.0 * maxi(plan.biomes[a.plan.biome].resource.room_size, plan.biomes[b.plan.biome].resource.room_size)


func _place_sign(biome: BiomePlan, zone: ZonePlan, sign_resource: SignResource, unit: String) -> void:
	var site := _place_forced(biome, zone, ObjectSite.Kind.SIGN, unit)
	if site != null:
		site.sign_resource = sign_resource


## In a Room of the Biome, or of the Zone when given, that doesn't teach or hold a landing; the Room
## becomes a Breather.
func _place_forced(biome: BiomePlan, zone: ZonePlan, kind: ObjectSite.Kind, unit: String) -> ObjectSite:
	var candidates: Array[GeneratedRoom] = []
	for room_plan in (zone.rooms if zone != null else biome.rooms):
		var room := graph.rooms[room_plan.key]
		if room.is_ordinary() and room.role != GeneratedRoom.Role.TEACHING:
			candidates.append(room)
	var site := _place(candidates, kind, unit)
	if site == null:
		push_error("World seed %d: no Room in %s can hold %s" % [plan.world_seed, zone.id if zone else biome.id, unit])
		return null
	graph.rooms[site.room_key].role = GeneratedRoom.Role.BREATHER
	return site


func _place_landing(door: ObjectSite, unit: String) -> void:
	var candidates: Array[GeneratedRoom] = []
	for room_plan in plan.biomes[door.destination_biome].rooms:
		var room := graph.rooms[room_plan.key]
		if room.is_ordinary():
			candidates.append(room)
	var landing := _place(candidates, ObjectSite.Kind.LANDING, unit)
	if landing == null:
		push_error("World seed %d: door %s has no Room to land in %s" % [plan.world_seed, door.key, door.destination_biome])
		return
	_landings[door] = landing
	_link(door)


## The first candidate in seeded order that may hold the site and keeps two room sizes from every
## spaced site, or the one keeping the most.
func _place(candidates: Array[GeneratedRoom], kind: ObjectSite.Kind, unit: String) -> ObjectSite:
	var order := candidates.duplicate()
	WorldPlanner._shuffle(order, plan.rng(WgHash.NS_SITES, unit))
	var best: GeneratedRoom
	var best_score := []
	for room: GeneratedRoom in order:
		if not _can_hold(kind, room, null):
			continue
		var occupied := 0 if room.sites.is_empty() else 1
		var ratio := minf(_ratio(null, _seed_spot(room), room), 1.0)
		if occupied == 0 and ratio >= 1.0:
			best = room
			break
		var score := [occupied, -ratio]
		if best == null or score < best_score:
			best = room
			best_score = score
	if best == null:
		return null
	var site := _add_site(best, kind, _free_spot(best))
	_spaced.append(site)
	_candidates[site] = candidates
	return site


## Signs, Professors and doors need a Room that is no landing's; landings a Room that no forced site
## made a Breather and the chance didn't either.
func _can_hold(kind: ObjectSite.Kind, room: GeneratedRoom, moving: ObjectSite) -> bool:
	if kind == ObjectSite.Kind.LANDING:
		return room.role != GeneratedRoom.Role.BREATHER
	return room.role != GeneratedRoom.Role.TEACHING and room.sites.all(func(site: ObjectSite) -> bool:
		return site == moving or site.kind != ObjectSite.Kind.LANDING)


## The least share of two room sizes a spot keeps from the other spaced sites.
func _ratio(site: ObjectSite, spot: Vector2, room: GeneratedRoom) -> float:
	var least := INF
	for other in _spaced:
		if other != site:
			least = minf(least, Vector2(spot).distance_to(Vector2(other.spot)) / spacing(room, graph.rooms[other.room_key]))
	return least


## Moves each site short of two room sizes to the free candidate Room keeping it farthest from the
## others, when that keeps it farther than where it stands.
func _spread() -> void:
	for _pass in SPREAD_PASSES:
		for site in _spaced:
			var room := graph.rooms[site.room_key]
			var best_ratio := _ratio(site, site.spot, room)
			if best_ratio >= 1.0:
				continue
			var best: GeneratedRoom
			for candidate: GeneratedRoom in _candidates[site]:
				if candidate == room or not candidate.sites.is_empty() or not _can_hold(site.kind, candidate, site):
					continue
				var ratio := _ratio(site, _seed_spot(candidate), candidate)
				if ratio > best_ratio + 0.01:
					best_ratio = ratio
					best = candidate
			if best != null:
				_move(site, best)
	for _pass in SPREAD_PASSES:
		_spread_spots()


## Improves the least spacing involving each site without changing its Room. Because a move is kept
## only when that site's least pairwise spacing improves, the World's least spacing never regresses.
func _spread_spots() -> void:
	for site in _spaced:
		var room := graph.rooms[site.room_key]
		var before := _ratio(site, site.spot, room)
		if before >= 1.0:
			continue
		var choice := _best_spot(room, site)
		if choice[1] > before + 0.01:
			site.spot = choice[0]


func _move(site: ObjectSite, room: GeneratedRoom) -> void:
	var old := graph.rooms[site.room_key]
	old.sites.erase(site)
	graph.sites.erase(site.key)
	site.room_key = room.key()
	site.spot = _free_spot(room)
	site.key = _site_key(room, site.kind)
	room.sites.append(site)
	graph.sites[site.key] = site
	if site.kind != ObjectSite.Kind.LANDING:
		room.role = GeneratedRoom.Role.BREATHER
		var forced := old.sites.any(func(other: ObjectSite) -> bool: return other.kind != ObjectSite.Kind.LANDING)
		old.role = GeneratedRoom.Role.BREATHER if forced or _chance.has(old) else GeneratedRoom.Role.TESTING
	for door in _landings:
		if door == site or _landings[door] == site:
			_link(door)


func _link(door: ObjectSite) -> void:
	var landing := _landings[door]
	landing.door_key = door.key
	door.destination_room = landing.room_key
	door.landing_key = landing.key


func _add_site(room: GeneratedRoom, kind: ObjectSite.Kind, spot: Vector2i) -> ObjectSite:
	var site := ObjectSite.new()
	site.kind = kind
	site.room_key = room.key()
	site.spot = spot
	site.key = _site_key(room, kind)
	room.sites.append(site)
	graph.sites[site.key] = site
	return site


## "<room key>/<kind>/<n>", n the first free count of that kind in the Room.
func _site_key(room: GeneratedRoom, kind: ObjectSite.Kind) -> String:
	var n := 0
	while graph.sites.has("%s/%s/%d" % [room.key(), ObjectSite.KIND_NAMES[kind], n]):
		n += 1
	return "%s/%s/%d" % [room.key(), ObjectSite.KIND_NAMES[kind], n]


func _seed_spot(room: GeneratedRoom) -> Vector2i:
	if not _seed_spots.has(room):
		_seed_spots[room] = graph.tile_of(room.seed)
	return _seed_spots[room]


## The seed when it already meets spacing; otherwise the owned interior point maximizing the least
## spacing from every other counted site. Points stay well inside the power cell so later interiors
## can reserve clear floor around them.
func _best_spot(room: GeneratedRoom, moving: ObjectSite) -> Array:
	var best := _seed_spot(room)
	var best_ratio := _ratio(moving, best, room) if _spot_is_free(room, best, moving) else -INF
	if best_ratio >= 1.0:
		return [best, best_ratio]
	var points: Array[Vector2] = [room.seed]
	for corner in room.polygon:
		for amount: float in [0.35, 0.5, 0.65]:
			points.append(room.seed.lerp(corner, amount))
	for n in room.polygon.size():
		var middle := room.polygon[n].lerp(room.polygon[(n + 1) % room.polygon.size()], 0.5)
		for amount: float in [0.35, 0.5, 0.65]:
			points.append(room.seed.lerp(middle, amount))
	var ranked: Array[Array] = []
	for point in points:
		ranked.append([_ratio(moving, point, room), point])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var seen := {best: true}
	for n in mini(SPOT_FINALISTS, ranked.size()):
		var point: Vector2 = ranked[n][1]
		var spot := graph.tile_of(point)
		if seen.has(spot) or graph.owner_at(spot) != room or not _spot_is_free(room, spot, moving):
			continue
		seen[spot] = true
		var ratio := _ratio(moving, spot, room)
		if ratio > best_ratio:
			best = spot
			best_ratio = ratio
	return [best, best_ratio]


func _spot_is_free(room: GeneratedRoom, spot: Vector2i, moving: ObjectSite) -> bool:
	return room.sites.all(func(site: ObjectSite) -> bool:
		return site == moving or Vector2(site.spot).distance_to(Vector2(spot)) >= SHARED_ROOM_GAP)


func _layout_is_valid() -> bool:
	for site in _spaced:
		var room := graph.rooms[site.room_key]
		if _ratio(site, site.spot, room) < MIN_SPACING:
			return false
		for other in room.sites:
			if other != site and other.spot == site.spot:
				return false
	return true


## The Room's seed, or when sites already stand there, the first point halfway to one of its corners
## that the Room owns and that keeps clear of them.
func _free_spot(room: GeneratedRoom) -> Vector2i:
	var points: Array[Vector2] = [room.seed]
	for corner in room.polygon:
		points.append(room.seed.lerp(corner, 0.5))
	for point in points:
		var spot := _seed_spot(room) if point == room.seed else graph.tile_of(point)
		if graph.owner_at(spot) != room:
			continue
		if room.sites.all(func(site: ObjectSite) -> bool: return Vector2(site.spot).distance_to(Vector2(spot)) >= SHARED_ROOM_GAP):
			return spot
	return _seed_spot(room)


## Glade -> Deepwood; an inner Ideal-path Biome -> either neighbour; a Side biome -> its parent.
func _door_targets(id: StringName) -> Array[StringName]:
	if plan.content.parents.has(id):
		return [plan.content.parents[id]]
	var path := plan.content.ideal_path
	var index := path.find(id)
	var out: Array[StringName] = []
	if index > 0:
		out.append(path[index - 1])
	if index < path.size() - 1:
		out.append(path[index + 1])
	return out


## The planned Boss nearest the Sign whose leader is the enemy it reveals; "" when it names none.
func _nearest_boss(sign_site: ObjectSite) -> String:
	var best := ""
	var best_distance := INF
	for id in plan.biomes:
		var boss := plan.biomes[id].boss
		if sign_site.sign_resource.reveals == null or boss.encounter.leader != sign_site.sign_resource.reveals:
			continue
		var distance := Vector2(sign_site.spot).distance_to(graph.rooms[boss.key].seed)
		if distance < best_distance:
			best_distance = distance
			best = boss.key
	return best
