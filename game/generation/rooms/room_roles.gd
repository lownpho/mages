class_name RoomRoles
extends RefCounted
## Rosters, Teaching rooms and chance Breathers for a WorldGraph. Set pieces keep the roles their
## World-plan entries give them; every other Room starts as a Testing room.
##
## Each route teaches every enemy of its rosters once, Hazards excepted: the Ideal path as one route,
## each Side route on its own. An enemy is introduced at the first route position whose Zone fields
## it at a Challenge its effective Entry challenge has reached; introductions at one position go in
## Entry-challenge order, shuffled where Entry challenges tie. Each takes the first free ordinary Room
## of a Zone fielding it that joins the route at or after that position, the route Room before
## off-route Rooms, or failing that the latest one before it.


static func assign_rosters(graph: WorldGraph) -> void:
	var plan := graph.plan
	for id in plan.biomes:
		var biome := plan.biomes[id]
		for zone in biome.zones:
			var roster: Dictionary[CreatureResource, int] = biome.resource.roster.duplicate()
			roster.merge(zone.resource.roster)
			if not roster.is_empty():
				# The Zone's lowest-entry non-Hazard enemies are eligible from its first Room, with any
				# Hazard entering no later, so none of its Rooms holds Hazards alone.
				var lowest := _lowest_entry(roster)
				var first := biome.route[zone.route_start].challenge
				for enemy in roster:
					if roster[enemy] <= lowest:
						roster[enemy] = mini(roster[enemy], first)
			for room_plan in zone.rooms:
				var room := graph.rooms[room_plan.key]
				room.roster = roster
				room.role = _set_piece_role(room_plan.kind)


static func teach(graph: WorldGraph) -> void:
	var plan := graph.plan
	var ideal: Array[BiomePlan] = []
	for id in plan.content.ideal_path:
		ideal.append(plan.biomes[id])
	_teach_route(graph, ideal)
	for side in plan.content.parents:
		_teach_route(graph, [plan.biomes[side]])


## Non-Teaching ordinary Rooms that hold no Object site become Breathers by their Biome's chance.
static func breathe(graph: WorldGraph) -> void:
	for key in graph.rooms:
		var room := graph.rooms[key]
		var chance := graph.plan.biomes[room.plan.biome].resource.breather_chance
		if room.role == GeneratedRoom.Role.TESTING and graph.plan.rng(WorldHash.NS_ROLES, "breather/" + key).randf() < chance:
			room.role = GeneratedRoom.Role.BREATHER


## The lowest Entry challenge among a roster's non-Hazard enemies, or among all of them when every
## one is a Hazard.
static func _lowest_entry(roster: Dictionary[CreatureResource, int]) -> int:
	var fighters := roster.keys().filter(func(enemy: CreatureResource) -> bool: return not enemy.is_hazard())
	var enemies := fighters if not fighters.is_empty() else roster.keys()
	return enemies.map(func(enemy: CreatureResource) -> int: return roster[enemy]).min()


static func _set_piece_role(kind: RoomPlan.Kind) -> GeneratedRoom.Role:
	match kind:
		RoomPlan.Kind.SPAWN:
			return GeneratedRoom.Role.SPAWN
		RoomPlan.Kind.BOSS:
			return GeneratedRoom.Role.BOSS
		RoomPlan.Kind.MINIBOSS:
			return GeneratedRoom.Role.MINIBOSS
		RoomPlan.Kind.RARE:
			return GeneratedRoom.Role.RARE
	return GeneratedRoom.Role.TESTING


static func _teach_route(graph: WorldGraph, biomes: Array[BiomePlan]) -> void:
	var plan := graph.plan
	var taught: Dictionary[CreatureResource, bool] = {}
	# [position along the route, Entry challenge, shuffle, enemy, Biome, route index]
	var introductions: Array[Array] = []
	var offset := 0
	for biome in biomes:
		for zone in biome.zones:
			var roster := graph.rooms[zone.rooms[0].key].roster
			var enemies: Array[CreatureResource] = []
			enemies.assign(roster.keys().filter(func(enemy: CreatureResource) -> bool: return not enemy.is_hazard()))
			enemies.sort_custom(func(a: CreatureResource, b: CreatureResource) -> bool: return a.resource_path < b.resource_path)
			for index in range(zone.route_start, zone.route_end()):
				var rng := plan.rng(WorldHash.NS_ROLES, "teach/%s/%d" % [biome.id, index])
				for enemy in enemies:
					if not taught.has(enemy) and roster[enemy] <= biome.route[index].challenge:
						taught[enemy] = true
						introductions.append([offset + index, roster[enemy], rng.randf(), enemy, biome, index])
		offset += biome.route.size()
	introductions.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	for introduction in introductions:
		var enemy: CreatureResource = introduction[3]
		var room := _teaching_room(graph, introduction[4], introduction[5], enemy)
		if room == null:
			push_error("World seed %d: no free Room in %s can teach %s" % [plan.world_seed, introduction[4].id, enemy.resource_path])
			continue
		room.role = GeneratedRoom.Role.TEACHING
		room.teaching = enemy


static func _teaching_room(graph: WorldGraph, biome: BiomePlan, index: int, enemy: CreatureResource) -> GeneratedRoom:
	var best: GeneratedRoom = null
	var best_score := []
	for room_plan in biome.rooms:
		var room := graph.rooms[room_plan.key]
		if not room.is_ordinary() or room.role != GeneratedRoom.Role.TESTING or not room.roster.has(enemy):
			continue
		var join := room_plan.join_index
		var score := [0, join, 0 if room_plan.is_on_route() else 1, room_plan.key] if join >= index else [1, -join, 0 if room_plan.is_on_route() else 1, room_plan.key]
		if best == null or score < best_score:
			best = room
			best_score = score
	return best
