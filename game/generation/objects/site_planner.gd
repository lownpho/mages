class_name SitePlanner
extends RefCounted
## Plans a WorldGraph's Object sites once Teaching rooms and chance Breathers are known.
##
## Every authored Sign stands once, in its Biome, or in its Zone when a Zone authors it; each Biome
## places its Professor count. Those Rooms must not teach; they keep their roles and their
## encounters, so an Object stands among the enemies rather than emptying a Room. Each Professor takes
## a seeded kind and looks one Biome onward (the next on the Ideal path, or the one after its parent
## for a Side biome, and nothing when that is sealed or the path ends): a portal Professor takes a
## landing in an ordinary Room there that isn't a Breather, and an item Professor draws its gift from
## that Biome's drop pool. Landings leave roles alone and may share a Room.
##
## Every choice takes the first candidate in seeded order at least two room sizes from the sites
## placed so far, or the farthest when none is. A spreading pass then moves each site still short of
## two room sizes to the candidate Room that keeps it farthest from the rest. The layout stands when
## every pair keeps MIN_SPACING of two room sizes. Signs reveal the nearest planned Boss or Miniboss
## their enemy leads. Chance Breathers left without sites draw one Object by weight from their
## Biome's and Zone's choices, or stay empty when they have none.
##
## Spots default to the Room's seed. When that would break spacing, placement searches deterministic
## interior points toward the Room's corners and edges; sites sharing a Room keep separate spots.

## Tiles between two sites sharing a Room.
const SHARED_ROOM_GAP := 6.0
## The least share of two room sizes every pair of spaced sites must keep. Placement still aims for
## the full two room sizes; near misses are accepted rather than failing the World.
const MIN_SPACING := 0.25
## Passes of the spreading step.
const SPREAD_PASSES := 4
## Only inverse-warp the most promising sampled points; ranking all of them in unwarped space is
## much cheaper and preserves the startup budget.
const SPOT_FINALISTS := 2

var graph: WorldGraph
var plan: WorldPlan
## Signs, Professors and landings, as they are placed.
var _spaced: Array[ObjectSite] = []
## Site -> the Rooms it may stand in.
var _candidates: Dictionary[ObjectSite, Array] = {}
## Portal Professor -> its landing.
var _landings: Dictionary[ObjectSite, ObjectSite] = {}
var _seed_spots: Dictionary[GeneratedRoom, Vector2i] = {}
## _spaced's spots and their Biomes' room sizes, flat for the spreading passes' inner loop: the
## spacing scan runs over every pair on every pass, and the Room and Biome lookups behind
## spacing() cost more than the arithmetic. _track() keeps them in step with _spaced.
var _spots := PackedVector2Array()
var _sizes := PackedFloat32Array()
## Biome -> its Rooms' size.
var _room_sizes: Dictionary[StringName, float] = {}


func _init(world_graph: WorldGraph) -> void:
	graph = world_graph
	plan = world_graph.plan


## Signs and Professors with their portals' landings, spread apart, with Sign reveals. False means
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
			var unit := "professor/%s/%d" % [id, n]
			var professor := _place_forced(biome, null, ObjectSite.Kind.PROFESSOR, unit)
			if professor == null:
				continue
			professor.opens_portal = plan.rng(WorldHash.NS_SITES, unit + "/kind").randi() % 2 == 0
			professor.destination_biome = _next_biome(id)
			if professor.destination_biome == &"":
				continue
			if professor.opens_portal:
				_place_landing(professor, "landing/" + unit)
			else:
				professor.reward_item = _reward_item(professor.destination_biome,
						plan.rng(WorldHash.NS_SITES, unit + "/gift"))
	_spread()
	if not _layout_is_valid():
		push_error("World seed %d: Object-site placement exhausted before every site was spaced" % plan.world_seed)
		return false
	for site in _spaced:
		if site.kind == ObjectSite.Kind.SIGN:
			site.reveal_key = _nearest_reveal(site)
			site.reveal_biome_key = _biome_entrance(site.sign_resource.reveals_biome)
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
		var roll := plan.rng(WorldHash.NS_SITES, "weighted/" + key).randi_range(1, total)
		for scene in scenes:
			roll -= weights[scene]
			if roll <= 0:
				var site := _add_site(room, ObjectSite.Kind.WEIGHTED, _free_spot(room))
				site.scene = scene
				break


## Two room sizes: the larger of the two Rooms' Biomes'.
func spacing(a: GeneratedRoom, b: GeneratedRoom) -> float:
	return 2.0 * maxf(_size_of(a), _size_of(b))


func _size_of(room: GeneratedRoom) -> float:
	var size: float = _room_sizes.get(room.plan.biome, 0.0)
	if size == 0.0:
		size = float(plan.biomes[room.plan.biome].resource.room_size)
		_room_sizes[room.plan.biome] = size
	return size


## Records a site's spot and size, appending it to _spaced the first time.
func _track(site: ObjectSite) -> void:
	var index := _spaced.find(site)
	if index < 0:
		index = _spaced.size()
		_spaced.append(site)
		_spots.append(Vector2.ZERO)
		_sizes.append(0.0)
	_spots[index] = Vector2(site.spot)
	_sizes[index] = _size_of(graph.rooms[site.room_key])


func _place_sign(biome: BiomePlan, zone: ZonePlan, sign_resource: SignResource, unit: String) -> void:
	var site := _place_forced(biome, zone, ObjectSite.Kind.SIGN, unit)
	if site != null:
		site.sign_resource = sign_resource


## In a Room of the Biome, or of the Zone when given, that doesn't teach or hold a landing. The Room
## keeps its role.
func _place_forced(biome: BiomePlan, zone: ZonePlan, kind: ObjectSite.Kind, unit: String) -> ObjectSite:
	var candidates: Array[GeneratedRoom] = []
	for room_plan in (zone.rooms if zone != null else biome.rooms):
		var room := graph.rooms[room_plan.key]
		if room.is_ordinary() and room.role != GeneratedRoom.Role.TEACHING:
			candidates.append(room)
	var site := _place(candidates, kind, unit)
	if site == null:
		push_error("World seed %d: no Room in %s can hold %s" % [plan.world_seed, zone.id if zone else biome.id, unit])
	return site


## The Biome a Professor looks onward to: the next on the Ideal path, or for a Side biome, the one
## after its parent. &"" where the Ideal path ends or the way onward is sealed, which leaves the
## Professor with nothing to give.
func _next_biome(id: StringName) -> StringName:
	var path := plan.content.ideal_path
	var index := path.find(plan.content.parents.get(id, id))
	if index < 0 or index + 1 >= path.size():
		return &""
	var next := path[index + 1]
	return &"" if plan.biomes[next].resource.sealed else next


## One of the items the Biome's enemies drop, drawn evenly among the distinct ones so a rare drop
## makes as likely a gift as a common one. Null when nothing filed there drops anything.
func _reward_item(biome_id: StringName, rng: RandomNumberGenerator) -> ItemResource:
	var items: Array[ItemResource] = []
	for creature in plan.content.biome_enemies(biome_id):
		for drop in creature.drops:
			if drop.item != null and not items.has(drop.item):
				items.append(drop.item)
	if items.is_empty():
		return null
	items.sort_custom(func(a: ItemResource, b: ItemResource) -> bool: return a.resource_path < b.resource_path)
	return items[rng.randi_range(0, items.size() - 1)]


## A portal Professor's landing.
func _place_landing(portal: ObjectSite, unit: String) -> void:
	var candidates: Array[GeneratedRoom] = []
	for room_plan in plan.biomes[portal.destination_biome].rooms:
		var room := graph.rooms[room_plan.key]
		if room.is_ordinary():
			candidates.append(room)
	var landing := _place(candidates, ObjectSite.Kind.LANDING, unit)
	if landing == null:
		push_error("World seed %d: %s has no Room to land in %s" % [plan.world_seed, portal.key, portal.destination_biome])
		return
	_landings[portal] = landing
	_link(portal)


## The first candidate in seeded order that may hold the site and keeps two room sizes from every
## spaced site, or the one keeping the most.
func _place(candidates: Array[GeneratedRoom], kind: ObjectSite.Kind, unit: String) -> ObjectSite:
	var order := candidates.duplicate()
	WorldPlanner._shuffle(order, plan.rng(WorldHash.NS_SITES, unit))
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
	_track(site)
	_candidates[site] = candidates
	return site


## Signs and Professors need a Room that is no landing's; landings a Room the chance didn't make a
## Breather, so a portal never arrives on top of a Breather's Object.
func _can_hold(kind: ObjectSite.Kind, room: GeneratedRoom, moving: ObjectSite) -> bool:
	if kind == ObjectSite.Kind.LANDING:
		return room.role != GeneratedRoom.Role.BREATHER
	return room.role != GeneratedRoom.Role.TEACHING and room.sites.all(func(site: ObjectSite) -> bool:
		return site == moving or site.kind != ObjectSite.Kind.LANDING)


## The least share of two room sizes a spot keeps from the other spaced sites. A caller that only
## wants to know whether the spot beats a ratio it already has passes it as least_wanted, and the
## scan stops at the first pair below it: the answer is then a lower bound, exact only when it comes
## back above least_wanted.
func _ratio(site: ObjectSite, spot: Vector2, room: GeneratedRoom, least_wanted := -INF) -> float:
	var size := _size_of(room)
	var point := Vector2(spot)
	var least := INF
	for n in _spaced.size():
		if _spaced[n] == site:
			continue
		var ratio := point.distance_to(_spots[n]) / (2.0 * maxf(size, _sizes[n]))
		if ratio < least:
			least = ratio
			if least <= least_wanted:
				return least
	return least


## Moves each site short of two room sizes to the free candidate Room keeping it farthest from the
## others, when that keeps it farther than where it stands.
## A pass that moves nothing leaves the layout it read, so the passes after it would move nothing
## either: both loops stop there.
func _spread() -> void:
	for _pass in SPREAD_PASSES:
		var moved := false
		for site in _spaced:
			var room := graph.rooms[site.room_key]
			var best_ratio := _ratio(site, site.spot, room)
			if best_ratio >= 1.0:
				continue
			var best: GeneratedRoom
			for candidate: GeneratedRoom in _candidates[site]:
				if candidate == room or not candidate.sites.is_empty() or not _can_hold(site.kind, candidate, site):
					continue
				var ratio := _ratio(site, _seed_spot(candidate), candidate, best_ratio + 0.01)
				if ratio > best_ratio + 0.01:
					best_ratio = ratio
					best = candidate
			if best != null:
				_move(site, best)
				moved = true
		if not moved:
			break
	for _pass in SPREAD_PASSES:
		if not _spread_spots():
			break


## Improves the least spacing involving each site without changing its Room. Because a move is kept
## only when that site's least pairwise spacing improves, the World's least spacing never regresses.
## Whether any site moved.
func _spread_spots() -> bool:
	var moved := false
	for site in _spaced:
		var room := graph.rooms[site.room_key]
		var before := _ratio(site, site.spot, room)
		if before >= 1.0:
			continue
		var choice := _best_spot(room, site)
		if choice[1] > before + 0.01:
			site.spot = choice[0]
			_track(site)
			moved = true
	return moved


func _move(site: ObjectSite, room: GeneratedRoom) -> void:
	var old := graph.rooms[site.room_key]
	old.sites.erase(site)
	graph.sites.erase(site.key)
	site.room_key = room.key()
	site.spot = _free_spot(room)
	site.key = _site_key(room, site.kind)
	room.sites.append(site)
	graph.sites[site.key] = site
	_track(site)
	for portal in _landings:
		if portal == site or _landings[portal] == site:
			_link(portal)


func _link(portal: ObjectSite) -> void:
	var landing := _landings[portal]
	landing.portal_key = portal.key
	portal.destination_room = landing.room_key
	portal.landing_key = landing.key


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
		_seed_spots[room] = graph.tile_of(room.seed_point)
	return _seed_spots[room]


## The seed when it already meets spacing; otherwise the owned interior point maximizing the least
## spacing from every other counted site. Points stay well inside the power cell so later interiors
## can reserve clear floor around them.
func _best_spot(room: GeneratedRoom, moving: ObjectSite) -> Array:
	var best := _seed_spot(room)
	var best_ratio := _ratio(moving, best, room) if _spot_is_free(room, best, moving) else -INF
	if best_ratio >= 1.0:
		return [best, best_ratio]
	var points: Array[Vector2] = [room.seed_point]
	for corner in room.polygon:
		for amount: float in [0.35, 0.5, 0.65]:
			points.append(room.seed_point.lerp(corner, amount))
	for n in room.polygon.size():
		var middle := room.polygon[n].lerp(room.polygon[(n + 1) % room.polygon.size()], 0.5)
		for amount: float in [0.35, 0.5, 0.65]:
			points.append(room.seed_point.lerp(middle, amount))
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
	var points: Array[Vector2] = [room.seed_point]
	for corner in room.polygon:
		points.append(room.seed_point.lerp(corner, 0.5))
	for point in points:
		var spot := _seed_spot(room) if point == room.seed_point else graph.tile_of(point)
		if graph.owner_at(spot) != room:
			continue
		if room.sites.all(func(site: ObjectSite) -> bool: return Vector2(site.spot).distance_to(Vector2(spot)) >= SHARED_ROOM_GAP):
			return spot
	return _seed_spot(room)


## The planned Boss or Miniboss nearest the Sign whose leader is the enemy it reveals; "" when it
## names none.
func _nearest_reveal(sign_site: ObjectSite) -> String:
	if sign_site.sign_resource.reveals == null:
		return ""
	var best := ""
	var best_distance := INF
	for room_plan in plan.set_pieces():
		if room_plan.kind != RoomPlan.Kind.BOSS and room_plan.kind != RoomPlan.Kind.MINIBOSS:
			continue
		if room_plan.encounter.leader != sign_site.sign_resource.reveals:
			continue
		var distance := Vector2(sign_site.spot).distance_to(graph.rooms[room_plan.key].seed_point)
		if distance < best_distance:
			best_distance = distance
			best = room_plan.key
	return best


## The key of the first route Room of the Biome a Sign points at; "" when it names none.
func _biome_entrance(biome: BiomeResource) -> String:
	if biome == null:
		return ""
	for id in plan.biomes:
		if plan.biomes[id].resource == biome:
			return plan.biomes[id].route[0].key
	return ""
