extends Node
## Headless tests for Layer 2. Run:
##   godot --headless --path game res://tests/worldgen/test_room_graph.tscn
## Builds full worlds (layout + every biome graph + contracts) and asserts: one connected
## component over all rooms world-wide; determinism; every room typed; contract crossings
## land on the correct rooms; BSP partition validity (leaves tile the region, sizes within the
## cap or demand-carved); quota counts AND size-window fits; world-unique uniqueness; depth.

var _config: GenConfig
var _T: int


func _ready() -> void:
	var fails: Array[String] = []
	_config = load("res://world_content/gen_config.tres")
	_T = _config.room_slot_tiles

	_test_connectivity(fails)
	_test_determinism(fails)
	_test_types(fails)
	_test_contracts(fails)
	_test_partition(fails)
	_test_world_unique(fails)
	_test_quotas(fails)
	_test_depth(fails)

	if fails.is_empty():
		print("ALL PASS")
	else:
		for f in fails:
			print("  FAIL: ", f)
		print("FAILED: %d" % fails.size())
	get_tree().quit(0 if fails.is_empty() else 1)


## Build every biome graph for a world into {biome_id -> BiomeGraph}.
func _build_world(seed_v: int) -> Dictionary:
	var spec := WorldLayout.build(seed_v, _config)
	var graphs: Dictionary = {}
	for p in spec.placements:
		graphs[p.id] = RoomGraph.build(spec, p.id, _config)
	return {"spec": spec, "graphs": graphs}


## Origin-slot id of the room reached by stepping across `p` from room `u`. Uniform for
## internal (same-biome) and external (adjacent-biome) passages: both resolve to a real slot
## across the border. Returns Vector2i(-1,-1) when the slot falls outside any biome.
func _neighbour_id(u: RoomSpec, p, spec: WorldSpec, graphs: Dictionary) -> Vector2i:
	var left := u.origin_slot.x
	var top := u.origin_slot.y
	var w := u.size_slots.x
	var h := u.size_slots.y
	@warning_ignore("integer_division")
	var mid: int = p.offset_tiles + p.width_tiles / 2
	var nx: int
	var ny: int
	match p.side:
		WorldSpec.SIDE_EAST:
			nx = left + w
			@warning_ignore("integer_division")
			ny = (top * _T + mid) / _T
		WorldSpec.SIDE_WEST:
			nx = left - 1
			@warning_ignore("integer_division")
			ny = (top * _T + mid) / _T
		WorldSpec.SIDE_SOUTH:
			ny = top + h
			@warning_ignore("integer_division")
			nx = (left * _T + mid) / _T
		_:
			ny = top - 1
			@warning_ignore("integer_division")
			nx = (left * _T + mid) / _T
	if nx < 0 or ny < 0:
		return Vector2i(-1, -1)
	var bid := spec.biome_at_slot(Vector2i(nx, ny))
	if bid == &"" or not graphs.has(bid):
		return Vector2i(-1, -1)
	var g: BiomeGraph = graphs[bid]
	return g.room_at(Vector2i(nx, ny) - g.origin_slot).origin_slot


func _test_connectivity(fails: Array[String]) -> void:
	for i in 200:
		var seed_v := 2_654_435_761 * i + 11
		var world := _build_world(seed_v)
		var spec: WorldSpec = world["spec"]
		var graphs: Dictionary = world["graphs"]
		# Adjacency keyed by origin_slot (globally unique). Every room is a node.
		var adj: Dictionary = {}
		var total := 0
		for bid in graphs:
			for u in graphs[bid].rooms:
				adj[u.origin_slot] = []
				total += 1
		for bid in graphs:
			for u in graphs[bid].rooms:
				for p in u.passages:
					var nb := _neighbour_id(u, p, spec, graphs)
					if nb != Vector2i(-1, -1):
						adj[u.origin_slot].append(nb)
		# BFS from any node.
		var start: Vector2i = adj.keys()[0]
		var seen: Dictionary = {start: true}
		var stack: Array = [start]
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			for nb in adj[cur]:
				if not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
		if seen.size() != total:
			fails.append("connectivity: %d/%d rooms reached at seed %d" % [seen.size(), total, seed_v])
			return
	print("connectivity: 200 seeds, single component world-wide")


func _test_determinism(fails: Array[String]) -> void:
	for i in 20:
		var seed_v := 40_503 * i + 7
		var spec := WorldLayout.build(seed_v, _config)
		for p in spec.placements:
			var a := RoomGraph.build(spec, p.id, _config)
			var b := RoomGraph.build(spec, p.id, _config)
			if not _graphs_equal(a, b):
				fails.append("determinism: biome %s differs on rebuild at seed %d" % [p.id, seed_v])
				return
	print("determinism: 20 seeds x all biomes rebuilt identically")


func _graphs_equal(a: BiomeGraph, b: BiomeGraph) -> bool:
	if a.rooms.size() != b.rooms.size() or a.slot_to_room != b.slot_to_room:
		return false
	for i in a.rooms.size():
		var ua: RoomSpec = a.rooms[i]
		var ub: RoomSpec = b.rooms[i]
		if ua.origin_slot != ub.origin_slot or ua.size_slots != ub.size_slots or ua.type_id != ub.type_id:
			return false
		if ua.depth != ub.depth or ua.biome_max_depth != ub.biome_max_depth \
				or ua.void_sides != ub.void_sides:
			return false
		if ua.passages.size() != ub.passages.size():
			return false
		for j in ua.passages.size():
			var pa = ua.passages[j]
			var pb = ub.passages[j]
			if pa.side != pb.side or pa.kind != pb.kind or pa.offset_tiles != pb.offset_tiles \
					or pa.width_tiles != pb.width_tiles or pa.external != pb.external:
				return false
	return true


func _test_types(fails: Array[String]) -> void:
	for i in 40:
		var seed_v := 15_485_863 * i + 3
		var world := _build_world(seed_v)
		for bid in world["graphs"]:
			for u in world["graphs"][bid].rooms:
				if u.type_id == &"":
					fails.append("types: empty type_id at seed %d biome %s" % [seed_v, bid])
					return
				if _config.room_type_by_id(u.type_id) == null:
					fails.append("types: unknown type '%s' at seed %d" % [u.type_id, seed_v])
					return
	print("types: 40 seeds, every room has exactly one known type")


func _test_contracts(fails: Array[String]) -> void:
	for i in 40:
		var seed_v := 32_452_843 * i + 5
		var world := _build_world(seed_v)
		var spec: WorldSpec = world["spec"]
		var graphs: Dictionary = world["graphs"]
		for by in spec.grid_h:
			for bx in spec.grid_w:
				var a := Vector2i(bx, by)
				var abid := spec.biome_at(a)
				if abid == &"":
					continue
				var east := Vector2i(bx + 1, by)
				var ebid := spec.biome_at(east)
				if ebid != &"" and ebid != abid:
					if not _check_border(spec, graphs, a, east, true, seed_v, fails):
						return
				var south := Vector2i(bx, by + 1)
				var sbid := spec.biome_at(south)
				if sbid != &"" and sbid != abid:
					if not _check_border(spec, graphs, a, south, false, seed_v, fails):
						return
	print("contracts: 40 seeds, every crossing lands on exactly one room each side")


## For the cell border (a, b) between two DIFFERENT biomes: each contract crossing must be
## carried by exactly one external DOOR on each side, at the matching absolute tile position.
## `horizontal` = b is east of a (vertical border).
func _check_border(spec: WorldSpec, graphs: Dictionary, a: Vector2i, b: Vector2i,
		horizontal: bool, seed_v: int, fails: Array[String]) -> bool:
	var ga: BiomeGraph = graphs[spec.biome_at(a)]
	var gb: BiomeGraph = graphs[spec.biome_at(b)]
	var bs := _config.biome_slots
	var side_a := WorldSpec.SIDE_EAST if horizontal else WorldSpec.SIDE_SOUTH
	var side_b := WorldSpec.SIDE_WEST if horizontal else WorldSpec.SIDE_NORTH
	for c in spec.get_contract(a, b):
		# Absolute tile position along the border axis (world tiles).
		var base: int = (a.y * bs + c.slot_index) if horizontal else (a.x * bs + c.slot_index)
		var abs_pos: int = base * _T + c.tile_offset
		var na := _count_external(ga, side_a, abs_pos, horizontal, c.width)
		var nb := _count_external(gb, side_b, abs_pos, horizontal, c.width)
		if na != 1 or nb != 1:
			fails.append("contracts: crossing slot %d on %s-%s carried by %d/%d rooms at seed %d"
					% [c.slot_index, a, b, na, nb, seed_v])
			return false
	return true


func _count_external(g: BiomeGraph, side: int, abs_pos: int, horizontal: bool, width: int) -> int:
	var n := 0
	for u in g.rooms:
		for p in u.passages:
			if not p.external or p.side != side or p.kind != RoomSpec.KIND_DOOR:
				continue
			var edge_start: int = u.origin_slot.y if horizontal else u.origin_slot.x
			var pos: int = edge_start * _T + p.offset_tiles
			if pos == abs_pos and p.width_tiles == width:
				n += 1
	return n


## Whether a room of `size` slots satisfies a type's size window (either orientation) —
## mirrors RoomGraph._fits.
func _fits_window(rt: RoomTypeDef, size: Vector2i) -> bool:
	if size.x >= rt.min_size_slots.x and size.x <= rt.max_size_slots.x \
			and size.y >= rt.min_size_slots.y and size.y <= rt.max_size_slots.y:
		return true
	return size.y >= rt.min_size_slots.x and size.y <= rt.max_size_slots.x \
			and size.x >= rt.min_size_slots.y and size.x <= rt.max_size_slots.y


func _test_partition(fails: Array[String]) -> void:
	var cap := _config.bsp_max_leaf_slots
	for i in 30:
		var seed_v := 49_979_687 * i + 13
		var world := _build_world(seed_v)
		for bid in world["graphs"]:
			var g: BiomeGraph = world["graphs"][bid]
			var s: Vector2i = g.size_slots
			# Every slot maps to a room whose rect contains it.
			for ly in s.y:
				for lx in s.x:
					var idx: int = g.slot_to_room[ly * s.x + lx]
					if idx < 0 or idx >= g.rooms.size():
						fails.append("partition: bad room index at seed %d biome %s" % [seed_v, bid])
						return
					var u: RoomSpec = g.rooms[idx]
					var lt: Vector2i = u.origin_slot - g.origin_slot   # region-local top-left slot
					if lx < lt.x or lx >= lt.x + u.size_slots.x or ly < lt.y or ly >= lt.y + u.size_slots.y:
						fails.append("partition: slot (%d,%d) outside its room at seed %d biome %s" % [lx, ly, seed_v, bid])
						return
					if lt.x < 0 or lt.y < 0 or lt.x + u.size_slots.x > s.x or lt.y + u.size_slots.y > s.y:
						fails.append("partition: room leaves region at seed %d biome %s" % [seed_v, bid])
						return
			# Leaves exactly tile the region (areas sum; owner-map coverage proved above).
			var area := 0
			for u in g.rooms:
				area += u.size_slots.x * u.size_slots.y
			if area != s.x * s.y:
				fails.append("partition: room areas sum %d != region %d at seed %d biome %s"
						% [area, s.x * s.y, seed_v, bid])
				return
			# BSP size cap: every leaf fits bsp_max_leaf_slots (either orientation) unless it is
			# a demand-carved quota leaf (equals some quota type's min_size_slots) or a 1x1 pin.
			for u in g.rooms:
				var sz: Vector2i = u.size_slots
				var fits_cap := (sz.x <= cap.x and sz.y <= cap.y) or (sz.y <= cap.x and sz.x <= cap.y)
				if fits_cap:
					continue
				var demand := false
				for rt in _config.rooms_for_biome(bid):
					if rt.min_per_biome > 0 and (sz == rt.min_size_slots
							or sz == Vector2i(rt.min_size_slots.y, rt.min_size_slots.x)):
						demand = true
						break
				if not demand:
					fails.append("partition: leaf %s exceeds cap %s and matches no demand at seed %d biome %s"
							% [sz, cap, seed_v, bid])
					return
	print("partition: 30 seeds, BSP leaves tile each region within the size cap")


func _test_world_unique(fails: Array[String]) -> void:
	for i in 30:
		var seed_v := 86_028_121 * i + 17
		var world := _build_world(seed_v)
		var spec: WorldSpec = world["spec"]
		var graphs: Dictionary = world["graphs"]
		# Each world-unique room sits on its assigned 1x1 room.
		for ur in spec.unique_rooms:
			var bid := spec.biome_at_slot(ur.world_slot)
			var g: BiomeGraph = graphs[bid]
			var host := g.room_at(ur.world_slot - g.origin_slot)
			if host.type_id != ur.type_id:
				fails.append("world_unique: type '%s' not on its host room at seed %d" % [ur.type_id, seed_v])
				return
			if host.size_slots != Vector2i.ONE:
				fails.append("world_unique: host of '%s' is %s, expected 1x1 at seed %d"
						% [ur.type_id, host.size_slots, seed_v])
				return
		# Each world-unique type appears at most once world-wide (exactly once when placed).
		for rt in _config.room_types:
			if rt.unique_scope != RoomTypeDef.UniqueScope.WORLD:
				continue
			var count := 0
			for bid in graphs:
				for u in graphs[bid].rooms:
					if u.type_id == rt.id:
						count += 1
			var placed := false
			for ur in spec.unique_rooms:
				if ur.type_id == rt.id:
					placed = true
			var expected := 1 if placed else 0
			if count != expected:
				fails.append("world_unique: type '%s' appears %d times (expected %d) at seed %d"
						% [rt.id, count, expected, seed_v])
				return
	print("world_unique: 30 seeds, each world-unique type placed at most once")


## Entrance depth: recompute per-biome BFS depth independently from passage GEOMETRY (internal
## passages only; sources = external-door rooms, or the centre-slot room for the starting/sealed
## biome) and require an exact match; biome_max_depth consistent. Difficulty placement: weighted-
## fill rooms never carry a type harder than their tier (fill only falls DOWN), and the
## difficulty-3 quota encounters land in the deepest quarter.
func _test_depth(fails: Array[String]) -> void:
	for i in 40:
		var seed_v := 67_867_967 * i + 9
		var world := _build_world(seed_v)
		var spec: WorldSpec = world["spec"]
		var graphs: Dictionary = world["graphs"]
		for bid in graphs:
			var g: BiomeGraph = graphs[bid]
			var is_starting: bool = bid == _config.starting_biome
			var by_origin: Dictionary = {}
			for idx in g.rooms.size():
				by_origin[g.rooms[idx].origin_slot] = idx
			# Independent BFS over internal passages.
			var depth: Array[int] = []
			depth.resize(g.rooms.size())
			depth.fill(-1)
			var queue: Array[int] = []
			if not is_starting:
				for idx in g.rooms.size():
					for p in g.rooms[idx].passages:
						if p.external:
							depth[idx] = 0
							queue.append(idx)
							break
			if queue.is_empty():
				var centre_local := Vector2i(g.size_slots.x >> 1, g.size_slots.y >> 1)
				var centre: int = by_origin[g.room_at(centre_local).origin_slot]
				depth[centre] = 0
				queue.append(centre)
			var head := 0
			while head < queue.size():
				var cur: int = queue[head]
				head += 1
				for p in g.rooms[cur].passages:
					if p.external:
						continue
					var nb_origin := _neighbour_id(g.rooms[cur], p, spec, graphs)
					if not by_origin.has(nb_origin):
						continue
					var nb: int = by_origin[nb_origin]
					if depth[nb] == -1:
						depth[nb] = depth[cur] + 1
						queue.append(nb)
			var max_depth := 0
			for idx in g.rooms.size():
				max_depth = maxi(max_depth, depth[idx])
			for idx in g.rooms.size():
				var u: RoomSpec = g.rooms[idx]
				if u.depth != depth[idx]:
					fails.append("depth: room %s has depth %d, geometry says %d (seed %d biome %s)"
							% [u.origin_slot, u.depth, depth[idx], seed_v, bid])
					return
				if u.biome_max_depth != max_depth:
					fails.append("depth: biome_max_depth %d != %d (seed %d biome %s)"
							% [u.biome_max_depth, max_depth, seed_v, bid])
					return
			# Difficulty placement. Quota types (min_per_biome > 0 on the def) place on the
			# nearest tier; everything else came from weighted fill, which only falls DOWN —
			# so a fill room's type difficulty never exceeds its tier.
			for u in g.rooms:
				var rt := _config.room_type_by_id(u.type_id)
				if rt == null or rt.min_per_biome > 0 \
						or rt.unique_scope == RoomTypeDef.UniqueScope.WORLD:
					continue
				if rt.difficulty > u.tier():
					fails.append("depth: fill room '%s' (difficulty %d) on tier-%d room (seed %d biome %s)"
							% [u.type_id, rt.difficulty, u.tier(), seed_v, bid])
					return
			# Difficulty-3 summit encounters sit on the deepest room available to them: every
			# room that ended up FILL-typed (not a quota/unique reservation) was still free when
			# the summit picked, so none that fits the summit's window may be strictly deeper.
			for rt in _config.rooms_for_biome(bid):
				if rt.min_per_biome <= 0 or rt.difficulty != 3:
					continue
				var summit_tier := -1
				for u in g.rooms:
					if u.type_id == rt.id:
						summit_tier = maxi(summit_tier, u.tier())
				if summit_tier < 0:
					continue
				for u in g.rooms:
					var urt := _config.room_type_by_id(u.type_id)
					var reserved: bool = urt == null or urt.min_per_biome > 0 \
							or urt.unique_scope == RoomTypeDef.UniqueScope.WORLD
					if not reserved and _fits_window(rt, u.size_slots) and u.tier() > summit_tier:
						fails.append("depth: summit '%s' at tier %d but fill room %s (tier %d) fits its window (seed %d biome %s)"
								% [rt.id, summit_tier, u.origin_slot, u.tier(), seed_v, bid])
						return
	print("depth: 40 seeds, BFS depth matches geometry; fill respects tiers; summits sit tier 3")


## Every room type's quota holds in its biome (min <= count <= max), and at least min_per_biome
## of its rooms FIT its size window — the BSP demand carving makes this a hard guarantee.
func _test_quotas(fails: Array[String]) -> void:
	for i in 30:
		var seed_v := 48_611 * i + 3
		var world := _build_world(seed_v)
		var graphs: Dictionary = world["graphs"]
		for bid in graphs:
			var g: BiomeGraph = graphs[bid]
			for rt in _config.rooms_for_biome(bid):
				var count := 0
				var fit_count := 0
				for u in g.rooms:
					if u.type_id == rt.id:
						count += 1
						if _fits_window(rt, u.size_slots):
							fit_count += 1
				if count < rt.min_per_biome or count > rt.max_per_biome:
					fails.append("quotas: %s '%s' count %d outside [%d, %d] at seed %d"
							% [bid, rt.id, count, rt.min_per_biome, rt.max_per_biome, seed_v])
					return
				if fit_count < rt.min_per_biome:
					fails.append("quotas: %s '%s' only %d/%d placements fit its size window at seed %d"
							% [bid, rt.id, fit_count, rt.min_per_biome, seed_v])
					return
	print("quotas: 30 seeds, every quota satisfied on size-fitting rooms")
