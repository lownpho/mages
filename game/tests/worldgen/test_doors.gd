extends Node
## Headless tests for the one-way warp doors (DoorLinks). Asserts:
##   - Determinism: the same seed builds an identical link map twice.
##   - Unchained: no door leads to itself, every destination is an ordinary room the map can
##     name, and destinations are NOT drawn from the door rooms — a landing that holds a door of
##     its own is chance, so the count of those stays a small fraction of all links.
##   - Placement: door counts honour each biome's doors_min/doors_max, doors only land in
##     ordinary rooms (never a pinned set-piece), and every door tile + its exit tile is
##     reachable floor.
##   - The room's spawn list carries the door, wearing the DESTINATION biome's art.
##   - Gates: an authored door naming a target_biome (the glades' cave mouth into the deepwood)
##     resolves to a fixed ordinary room in that biome, the same one on a rebuild.
##   - Variety: different seeds put doors in different rooms and link them differently.
## Run: godot --headless --path game res://tests/worldgen/test_doors.tscn

const SEEDS := 25


func _ready() -> void:
	var fails: Array[String] = []
	var config: GenConfig = load("res://world_content/gen_config.tres")

	var maps: Array[Dictionary] = []
	var total_doors := 0
	var cross_biome := 0
	var landed_on_door := 0
	var gates := 0
	for i in SEEDS:
		var seed_v := 15_485_863 * i + 7
		var streamer := WorldStreamer.new()
		streamer.config = config
		streamer.build_world(seed_v)
		var links := streamer.door_links()

		# --- Determinism: a second build off the same seed must agree door for door ----------
		var other := WorldStreamer.new()
		other.config = config
		other.build_world(seed_v)
		var a := _map_of(links)
		var b := _map_of(other.door_links())
		if a != b:
			fails.append("link map not deterministic (seed %d)" % seed_v)
		maps.append(a)

		# --- Unchained: every landing is an ordinary room, picked without regard for doors -----
		for slot in a:
			var dest: Vector2i = a[slot]
			if dest == slot:
				fails.append("door at %s leads to itself (seed %d)" % [slot, seed_v])
			var dest_spec: RoomSpec = links.room_at(dest)
			if dest_spec == null:
				fails.append("door at %s lands in %s, which names no room (seed %d)"
						% [slot, dest, seed_v])
			else:
				var drt := config.room_type_by_id(dest_spec.type_id)
				if drt == null or drt.weight <= 0 \
						or drt.unique_scope != RoomTypeDef.UniqueScope.NONE:
					fails.append("door at %s lands in pinned/unique room %s (seed %d)"
							% [slot, dest_spec.type_id, seed_v])
			if a.has(dest):
				landed_on_door += 1   # only chance — counted, not failed
			if links.room_at(slot) == null:
				fails.append("door at %s has no room spec (seed %d)" % [slot, seed_v])
		total_doors += links.count()

		# --- Per-biome counts and room eligibility --------------------------------------------
		for p in streamer.world_spec.placements:
			var biome := config.biome_by_id(p.id)
			var placed := 0
			for slot in a:
				var spec: RoomSpec = links.room_at(slot)
				if spec.biome_id == p.id:
					placed += 1
					var rt := config.room_type_by_id(spec.type_id)
					if rt.weight <= 0:
						fails.append("door in pinned room type %s (seed %d)"
								% [spec.type_id, seed_v])
					if rt.unique_scope != RoomTypeDef.UniqueScope.NONE:
						fails.append("door in world-unique room %s (seed %d)"
								% [spec.type_id, seed_v])
					if links.room_at(a[slot]).biome_id != p.id:
						cross_biome += 1
			# Both ends are firm now that linking drops nothing: every room picked keeps its door.
			if placed > biome.doors_max:
				fails.append("%s placed %d doors over its max %d (seed %d)"
						% [p.id, placed, biome.doors_max, seed_v])
			if biome.doors_max > 0 and placed < biome.doors_min:
				fails.append("%s placed %d doors, min %d (seed %d)"
						% [p.id, placed, biome.doors_min, seed_v])

		# --- The door reaches the room's spawn list, and both tiles are walkable --------------
		for slot in a:
			var spec: RoomSpec = links.room_at(slot)
			var out := streamer.get_room_output(spec)
			var doors := []
			for sp in out.spawns:
				if sp.has("feature") and sp["feature_data"] is DoorResource:
					doors.append(sp)
			if doors.size() != 1:
				fails.append("room %s carries %d door spawns, want 1 (seed %d)"
						% [slot, doors.size(), seed_v])
				continue
			var tile: Vector2i = doors[0]["tile"]
			if out.reachability_map[tile.y * out.width + tile.x] != 1:
				fails.append("door tile %s unreachable in room %s (seed %d)"
						% [tile, slot, seed_v])
			# However the player walks in, they come out on walkable floor — and straight on
			# whenever that side is clear, so holding one direction carries them through.
			var headings: Array[Vector2i] = [Vector2i.ZERO, Vector2i(0, -1), Vector2i(0, 1),
					Vector2i(1, 0), Vector2i(-1, 0)]
			for h in headings:
				var exit_t := DoorLinks.exit_tile(out, h)
				if out.reachability_map[exit_t.y * out.width + exit_t.x] != 1:
					fails.append("exit tile %s (heading %s) unreachable in room %s (seed %d)"
							% [exit_t, h, slot, seed_v])
				if h != Vector2i.ZERO and _reachable(out, tile + h) and exit_t != tile + h:
					fails.append("exit tile %s ignored a clear heading %s in room %s (seed %d)"
							% [exit_t, h, slot, seed_v])
				if h != Vector2i.ZERO and exit_t == tile - h and _has_side_exit(out, tile, h):
					fails.append("exit doubled back on heading %s with a side clear, room %s (seed %d)"
							% [h, slot, seed_v])
			var res: DoorResource = doors[0]["feature_data"]
			if res.target_slot != a[slot]:
				fails.append("door spawn at %s targets %s, want %s (seed %d)"
						% [slot, res.target_slot, a[slot], seed_v])
			var dest_style: int = config.biome_by_id(links.room_at(a[slot]).biome_id).door_style
			if res.style != dest_style:
				fails.append("door at %s wears style %d, want the destination's %d (seed %d)"
						% [slot, res.style, dest_style, seed_v])
			# The warp destination resolves to a real world position.
			if streamer.door_exit_position(a[slot]) == Vector2.INF:
				fails.append("no exit position for %s (seed %d)" % [a[slot], seed_v])

		# --- Authored gates: a hand-placed door naming a biome lands in that biome, and stays put
		var placed_biomes := {}
		for p in streamer.world_spec.placements:
			placed_biomes[p.id] = true
		for p in streamer.world_spec.placements:
			for room in streamer.biome_graph(p.id).rooms:
				var rt := config.room_type_by_id(room.type_id)
				if rt == null:
					continue
				var want: StringName = _gate_biome(rt)
				if want == &"":
					continue
				var res := _gate_door(streamer.get_room_output(room))
				if not placed_biomes.has(want):
					# The gate's biome missed this world: the door is dropped, never left dead.
					if res != null:
						fails.append("gate %s kept a door with %s absent (seed %d)"
								% [room.type_id, want, seed_v])
					continue
				if res == null:
					fails.append("gate room %s carries no door (seed %d)"
							% [room.type_id, seed_v])
					continue
				gates += 1
				var dest_spec: RoomSpec = links.room_at(res.target_slot)
				if dest_spec == null:
					fails.append("gate %s targets %s, which names no room (seed %d)"
							% [room.type_id, res.target_slot, seed_v])
				elif dest_spec.biome_id != want:
					fails.append("gate %s targets %s in %s, want %s (seed %d)"
							% [room.type_id, res.target_slot, dest_spec.biome_id, want, seed_v])
				elif streamer.door_exit_position(res.target_slot) == Vector2.INF:
					fails.append("gate %s has no exit position (seed %d)"
							% [room.type_id, seed_v])
				var twin := _gate_door(other.get_room_output(room))
				if twin == null or twin.target_slot != res.target_slot:
					fails.append("gate %s moved on a rebuild (seed %d)" % [room.type_id, seed_v])

		other.free()
		streamer.free()

	# --- Variety: no two seeds may lay their doors out the same way --------------------------
	var repeats := 0
	for i in maps.size():
		for j in range(i + 1, maps.size()):
			if maps[i] == maps[j]:
				repeats += 1
	if repeats > 0:
		fails.append("%d seed pairs produced an identical link map" % repeats)
	if total_doors == 0:
		fails.append("no doors placed in %d seeds" % SEEDS)
	# Destinations are rolled over EVERY ordinary room, so landing on another door room is a
	# coincidence — with a few doors among hundreds of rooms it must stay rare. A chained
	# implementation would score 100%.
	if total_doors > 0 and landed_on_door * 3 > total_doors:
		fails.append("%d of %d doors land in another door's room — destinations look chained"
				% [landed_on_door, total_doors])
	if gates == 0:
		fails.append("no authored gate doors resolved in %d seeds" % SEEDS)

	await _check_live_door(fails)

	print("== doors ==")
	print("  %d seeds, %d doors, %d links crossing a biome" % [SEEDS, total_doors, cross_biome])
	print("  %d gates resolved, %d links landing in another door's room (chance)"
			% [gates, landed_on_door])

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: %s" % f)
	get_tree().quit(0 if fails.is_empty() else 1)


## The live node: a warp door must stay silent while the player stands in it (a streamed-in door
## can appear right under them, including one in the room a warp just dropped them in), then fire
## once they step off and walk back in — that guard, with the global cooldown, is what stops an
## arrival being flung straight on again.
func _check_live_door(fails: Array[String]) -> void:
	var door: Node2D = load("res://worldgen/runtime/door.tscn").instantiate()
	door.target_slot = Vector2i(3, 4)
	var body := CharacterBody2D.new()
	body.collision_layer = 16   # Player
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8, 8)
	shape.shape = rect
	body.add_child(shape)
	var fired: Array[Vector2i] = []
	var headings: Array[Vector2i] = []
	GlobalEvent.warp_requested.connect(
			func(slot: Vector2i, _b: Node2D, heading: Vector2i) -> void:
				fired.append(slot)
				headings.append(heading))
	add_child(door)
	add_child(body)   # spawned standing in the door, exactly like a warp arrival
	await _physics_frames(3)
	if not fired.is_empty():
		fails.append("door fired while the player stood in it — a warp would bounce straight back")

	body.global_position = Vector2(0, 200)     # step off below the door: the door arms
	await _physics_frames(3)
	body.velocity = Vector2(0, -60)            # walk back in heading north
	body.global_position = Vector2.ZERO
	await _physics_frames(3)
	if fired.size() != 1:
		fails.append("armed door fired %d times, want 1" % fired.size())
	elif fired[0] != Vector2i(3, 4):
		fails.append("door emitted target %s, want (3, 4)" % fired[0])
	if headings.size() == 1 and headings[0] != Vector2i(0, -1):
		fails.append("door read heading %s, want north (0, -1)" % headings[0])

	# The global cooldown: stepping off and straight back in again inside the second is refused,
	# whichever door you reach — so a landing beside a door can't fling you on immediately.
	var second: Node2D = load("res://worldgen/runtime/door.tscn").instantiate()
	second.target_slot = Vector2i(5, 6)
	second.global_position = Vector2(0, 200)
	add_child(second)
	body.global_position = Vector2(0, 400)
	await _physics_frames(3)
	body.global_position = Vector2(0, 200)   # walk into a DIFFERENT door within the cooldown
	await _physics_frames(3)
	if fired.size() != 1:
		fails.append("a door fired inside the global cooldown")
	second.queue_free()
	door.queue_free()
	body.queue_free()


## The biome an authored GATE door on this room type names, or &"" when it carries none — the
## deepwood cave mouths in the glades are the only ones today.
static func _gate_biome(rt: RoomTypeDef) -> StringName:
	for f in rt.features:
		if f.data is DoorResource and f.data.target_biome != &"":
			return f.data.target_biome
	return &""


## The DoorResource of the door in a finished room, or null when it holds none.
static func _gate_door(out: RoomOutput) -> DoorResource:
	for sp in out.spawns:
		if sp.get("feature_data") is DoorResource:
			return sp["feature_data"]
	return null


func _reachable(out: RoomOutput, t: Vector2i) -> bool:
	if t.x < 0 or t.y < 0 or t.x >= out.width or t.y >= out.height:
		return false
	return out.reachability_map[t.y * out.width + t.x] == 1


## Either tile flanking the door on a heading — the two exits that beat doubling back.
func _has_side_exit(out: RoomOutput, tile: Vector2i, heading: Vector2i) -> bool:
	return _reachable(out, tile + Vector2i(-heading.y, heading.x)) \
			or _reachable(out, tile + Vector2i(heading.y, -heading.x))


func _physics_frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


## Plain slot -> slot Dictionary, so two maps compare with ==.
func _map_of(links: DoorLinks) -> Dictionary:
	var out := {}
	for slot in links.slots():
		out[slot] = links.target_of(slot)
	return out
