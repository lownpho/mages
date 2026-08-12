extends Node
## Headless tests for the two-way warp doors (DoorLinks). Asserts:
##   - Determinism: the same seed builds an identical link map twice.
##   - Symmetry: every link is two-way, no door pairs with itself, counts are even.
##   - Placement: door counts honour each biome's doors_min/doors_max, doors only land in
##     ordinary rooms (never a pinned set-piece), and every door tile + its exit tile is
##     reachable floor.
##   - The room's spawn list carries the door, wearing the DESTINATION biome's art.
##   - Variety: different seeds put doors in different rooms and pair them differently.
## Run: godot --headless --path game res://tests/worldgen/test_doors.tscn

const SEEDS := 25


func _ready() -> void:
	var fails: Array[String] = []
	var config: GenConfig = load("res://world_content/gen_config.tres")

	var maps: Array[Dictionary] = []
	var total_doors := 0
	var cross_biome := 0
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
		other.free()

		# --- Symmetry ------------------------------------------------------------------------
		if links.count() % 2 != 0:
			fails.append("odd door count %d (seed %d)" % [links.count(), seed_v])
		for slot in a:
			var twin: Vector2i = a[slot]
			if twin == slot:
				fails.append("door at %s links to itself (seed %d)" % [slot, seed_v])
			elif links.partner_of(twin) != slot:
				fails.append("link %s -> %s is one-way (seed %d)" % [slot, twin, seed_v])
			if links.room_at(slot) == null:
				fails.append("door at %s has no room spec (seed %d)" % [slot, seed_v])
		total_doors += links.count()

		# --- Per-biome counts and room eligibility --------------------------------------------
		var short_biomes := 0   # the odd door out is dropped world-wide, costing ONE biome one door
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
			# The max is firm. The min is a PICK count: an odd world-wide total drops one door,
			# so exactly one biome may come out one short — never two, never more than one short.
			if placed > biome.doors_max:
				fails.append("%s placed %d doors over its max %d (seed %d)"
						% [p.id, placed, biome.doors_max, seed_v])
			if biome.doors_max > 0 and placed < biome.doors_min:
				short_biomes += 1
				if placed < biome.doors_min - 1:
					fails.append("%s placed %d doors, min %d (seed %d)"
							% [p.id, placed, biome.doors_min, seed_v])
		if short_biomes > 1:
			fails.append("%d biomes short of their door min (seed %d)" % [short_biomes, seed_v])

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

	await _check_live_door(fails)

	print("== doors ==")
	print("  %d seeds, %d doors, %d links crossing a biome" % [SEEDS, total_doors, cross_biome])

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: %s" % f)
	get_tree().quit(0 if fails.is_empty() else 1)


## The live node: a warp door must stay silent while the player stands in it (a warp lands them
## beside their destination door, and a streamed-in door can appear right under them), then fire
## once they step off and walk back in — that guard is what stops a link bouncing them straight
## back where they came from.
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
	door.queue_free()
	body.queue_free()


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
		out[slot] = links.partner_of(slot)
	return out
