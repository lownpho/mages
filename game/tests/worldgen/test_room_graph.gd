extends Node
## Headless tests for Layer 2. Run:
##   godot --headless --path game res://tests/worldgen/test_room_graph.tscn
## Builds full worlds (layout + every biome graph + contracts) and asserts: one connected
## component over all room units world-wide; determinism; every unit typed; contract crossings
## land on the correct units; merged-unit partition validity; world-unique uniqueness.

var _config: GenConfig
var _S: int
var _T: int


func _ready() -> void:
	var fails: Array[String] = []
	_config = load("res://world_content/gen_config.tres")
	_S = _config.biome_slots
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


## Build every biome graph for a world into {Vector2i -> BiomeGraph}.
func _build_world(seed: int) -> Dictionary:
	var spec := WorldLayout.build(seed, _config)
	var graphs: Dictionary = {}
	for by in spec.grid_h:
		for bx in spec.grid_w:
			var c := Vector2i(bx, by)
			graphs[c] = RoomGraph.build(spec, c, _config)
	return {"spec": spec, "graphs": graphs}


## Unit-id (world slot coord) of the unit reached by stepping across `p` from `spec`. Uniform for
## internal (same-biome) and external (adjacent-biome) passages: both resolve to a real slot across
## the border. Returns Vector2i(-1,-1) if the slot falls outside the world.
func _neighbour_id(spec: RoomSpec, p, graphs: Dictionary) -> Vector2i:
	var left := spec.origin_slot.x
	var top := spec.origin_slot.y
	var w := spec.size_slots.x
	var h := spec.size_slots.y
	var mid: int = p.offset_tiles + p.width_tiles / 2
	var nx: int
	var ny: int
	match p.side:
		WorldSpec.SIDE_EAST:
			nx = left + w
			ny = (top * _T + mid) / _T
		WorldSpec.SIDE_WEST:
			nx = left - 1
			ny = (top * _T + mid) / _T
		WorldSpec.SIDE_SOUTH:
			ny = top + h
			nx = (left * _T + mid) / _T
		_:
			ny = top - 1
			nx = (left * _T + mid) / _T
	if nx < 0 or ny < 0:
		return Vector2i(-1, -1)
	var bc := Vector2i(nx / _S, ny / _S)
	if not graphs.has(bc):
		return Vector2i(-1, -1)
	var g: BiomeGraph = graphs[bc]
	var local := Vector2i(nx - bc.x * _S, ny - bc.y * _S)
	return g.room_at(local).origin_slot


func _test_connectivity(fails: Array[String]) -> void:
	for i in 200:
		var seed := 2_654_435_761 * i + 11
		var world := _build_world(seed)
		var graphs: Dictionary = world["graphs"]
		# Adjacency keyed by origin_slot (globally unique). Every room is a node.
		var adj: Dictionary = {}
		var total := 0
		for c in graphs:
			for u in graphs[c].rooms:
				adj[u.origin_slot] = []
				total += 1
		for c in graphs:
			for u in graphs[c].rooms:
				for p in u.passages:
					var nb := _neighbour_id(u, p, graphs)
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
			fails.append("connectivity: %d/%d units reached at seed %d" % [seen.size(), total, seed])
			return
	print("connectivity: 200 seeds, single component world-wide")


func _test_determinism(fails: Array[String]) -> void:
	for i in 20:
		var seed := 40_503 * i + 7
		var spec := WorldLayout.build(seed, _config)
		for by in spec.grid_h:
			for bx in spec.grid_w:
				var c := Vector2i(bx, by)
				var a := RoomGraph.build(spec, c, _config)
				var b := RoomGraph.build(spec, c, _config)
				if not _graphs_equal(a, b):
					fails.append("determinism: biome %s differs on rebuild at seed %d" % [c, seed])
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
		if ua.depth != ub.depth or ua.biome_max_depth != ub.biome_max_depth:
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
		var seed := 15_485_863 * i + 3
		var world := _build_world(seed)
		for c in world["graphs"]:
			for u in world["graphs"][c].rooms:
				if u.type_id == &"":
					fails.append("types: empty type_id at seed %d biome %s" % [seed, c])
					return
				if _config.room_type_by_id(u.type_id) == null:
					fails.append("types: unknown type '%s' at seed %d" % [u.type_id, seed])
					return
	print("types: 40 seeds, every unit has exactly one known type")


func _test_contracts(fails: Array[String]) -> void:
	for i in 40:
		var seed := 32_452_843 * i + 5
		var world := _build_world(seed)
		var spec: WorldSpec = world["spec"]
		var graphs: Dictionary = world["graphs"]
		for by in spec.grid_h:
			for bx in spec.grid_w:
				var a := Vector2i(bx, by)
				if bx + 1 < spec.grid_w:
					if not _check_border(spec, graphs, a, Vector2i(bx + 1, by), true, seed, fails):
						return
				if by + 1 < spec.grid_h:
					if not _check_border(spec, graphs, a, Vector2i(bx, by + 1), false, seed, fails):
						return
	print("contracts: 40 seeds, every crossing lands on exactly one unit each side")


## For border (a, b): each contract crossing must be carried by exactly one external DOOR on each
## side, at the matching absolute tile position. `horizontal` = b is east of a (vertical border).
func _check_border(spec: WorldSpec, graphs: Dictionary, a: Vector2i, b: Vector2i,
		horizontal: bool, seed: int, fails: Array[String]) -> bool:
	var ga: BiomeGraph = graphs[a]
	var gb: BiomeGraph = graphs[b]
	var side_a := WorldSpec.SIDE_EAST if horizontal else WorldSpec.SIDE_SOUTH
	var side_b := WorldSpec.SIDE_WEST if horizontal else WorldSpec.SIDE_NORTH
	for c in spec.get_contract(a, b):
		# Absolute tile position along the border axis (world tiles).
		var base: int = (a.y * _S + c.slot_index) if horizontal else (a.x * _S + c.slot_index)
		var abs_pos: int = base * _T + c.tile_offset
		var na := _count_external(ga, side_a, abs_pos, horizontal, c.width)
		var nb := _count_external(gb, side_b, abs_pos, horizontal, c.width)
		if na != 1 or nb != 1:
			fails.append("contracts: crossing slot %d on %s-%s carried by %d/%d units at seed %d"
					% [c.slot_index, a, b, na, nb, seed])
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


func _test_partition(fails: Array[String]) -> void:
	for i in 30:
		var seed := 49_979_687 * i + 13
		var world := _build_world(seed)
		for c in world["graphs"]:
			var g: BiomeGraph = world["graphs"][c]
			# Every slot maps to a unit whose rect contains it.
			for ly in _S:
				for lx in _S:
					var idx: int = g.slot_to_room[ly * _S + lx]
					if idx < 0 or idx >= g.rooms.size():
						fails.append("partition: bad unit index at seed %d biome %s" % [seed, c])
						return
					var u: RoomSpec = g.rooms[idx]
					var lt: Vector2i = u.origin_slot - c * _S   # local top-left slot
					if lx < lt.x or lx >= lt.x + u.size_slots.x or ly < lt.y or ly >= lt.y + u.size_slots.y:
						fails.append("partition: slot (%d,%d) outside its unit at seed %d biome %s" % [lx, ly, seed, c])
						return
					if lt.x < 0 or lt.y < 0 or lt.x + u.size_slots.x > _S or lt.y + u.size_slots.y > _S:
						fails.append("partition: unit leaves biome at seed %d biome %s" % [seed, c])
						return
	print("partition: 30 seeds, slot_to_room is a valid in-biome partition")


func _test_world_unique(fails: Array[String]) -> void:
	for i in 30:
		var seed := 86_028_121 * i + 17
		var world := _build_world(seed)
		var spec: WorldSpec = world["spec"]
		var graphs: Dictionary = world["graphs"]
		# Each world-unique room sits on its assigned unit.
		for ur in spec.unique_rooms:
			var g: BiomeGraph = graphs[ur.biome_coord]
			var host := g.room_at(ur.local_slot)
			if host.type_id != ur.type_id:
				fails.append("world_unique: type '%s' not on its host unit at seed %d" % [ur.type_id, seed])
				return
		# Each world-unique type appears at most once world-wide (exactly once when placed).
		for rt in _config.room_types:
			if rt.unique_scope != RoomTypeDef.UniqueScope.WORLD:
				continue
			var count := 0
			for c in graphs:
				for u in graphs[c].rooms:
					if u.type_id == rt.id:
						count += 1
			var placed := false
			for ur in spec.unique_rooms:
				if ur.type_id == rt.id:
					placed = true
			var expected := 1 if placed else 0
			if count != expected:
				fails.append("world_unique: type '%s' appears %d times (expected %d) at seed %d"
						% [rt.id, count, expected, seed])
				return
	print("world_unique: 30 seeds, each world-unique type placed at most once")


## Entrance depth: recompute per-biome BFS depth independently from passage GEOMETRY (internal
## passages only; sources = external-door rooms, or the centre-slot room for the starting biome)
## and require an exact match; biome_max_depth consistent. Difficulty placement: weighted-fill
## rooms never carry a type harder than their tier (fill only falls DOWN), and the difficulty-3
## quota encounters (boss, deepwood_arena) land in the deepest quarter.
func _test_depth(fails: Array[String]) -> void:
	for i in 40:
		var seed := 67_867_967 * i + 9
		var world := _build_world(seed)
		var spec: WorldSpec = world["spec"]
		var graphs: Dictionary = world["graphs"]
		for c in graphs:
			var g: BiomeGraph = graphs[c]
			var is_starting: bool = spec.biome_at(c) == _config.starting_biome
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
				var centre: int = by_origin[g.room_at(Vector2i(_S >> 1, _S >> 1)).origin_slot]
				depth[centre] = 0
				queue.append(centre)
			var head := 0
			while head < queue.size():
				var cur: int = queue[head]
				head += 1
				for p in g.rooms[cur].passages:
					if p.external:
						continue
					var nb_origin := _neighbour_id(g.rooms[cur], p, graphs)
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
							% [u.origin_slot, u.depth, depth[idx], seed, c])
					return
				if u.biome_max_depth != max_depth:
					fails.append("depth: biome_max_depth %d != %d (seed %d biome %s)"
							% [u.biome_max_depth, max_depth, seed, c])
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
							% [u.type_id, rt.difficulty, u.tier(), seed, c])
					return
			# The difficulty-3 summit encounters sit in the deepest quarter.
			for u in g.rooms:
				if (u.type_id == &"glade_boss_d3" or u.type_id == &"deepwood_arena") and u.tier() != 3:
					fails.append("depth: summit '%s' on tier-%d room (seed %d biome %s)"
							% [u.type_id, u.tier(), seed, c])
					return
	print("depth: 40 seeds, BFS depth matches geometry; fill respects tiers; summits sit tier 3")


## Every room type's quota holds in its biome: min_per_biome <= count <= max_per_biome.
func _test_quotas(fails: Array[String]) -> void:
	for i in 30:
		var seed := 48_611 * i + 3
		var world := _build_world(seed)
		var spec: WorldSpec = world["spec"]
		var graphs: Dictionary = world["graphs"]
		for by in spec.grid_h:
			for bx in spec.grid_w:
				var c := Vector2i(bx, by)
				var biome := _config.biome_by_id(spec.biome_at(c))
				var g: BiomeGraph = graphs[c]
				for rt in _config.rooms_for_biome(biome.id):
					var count := 0
					for u in g.rooms:
						if u.type_id == rt.id:
							count += 1
					if count < rt.min_per_biome or count > rt.max_per_biome:
						fails.append("quotas: %s '%s' count %d outside [%d, %d] at seed %d"
								% [biome.id, rt.id, count, rt.min_per_biome, rt.max_per_biome, seed])
						return
	print("quotas: 30 seeds, every room type's min/max satisfied")
