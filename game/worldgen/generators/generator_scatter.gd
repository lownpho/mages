class_name RoomGenScatter
## Scatter generator (spec §8.2): N blocker CLUMPS at rejection-sampled positions with a
## minimum spacing between clump centers. clump_min/max = 1 gives classic lone rocks/trees;
## larger values grow each center into a touching grove by deterministic neighbour walk.
## Count scales with merged-unit slot area.
extends RoomGenBase

const ATTEMPTS_PER_BLOCKER := 20


func run(grid: PackedByteArray, protected: PackedByteArray, w: int, h: int,
		rng: RandomNumberGenerator, spec: RoomSpec, config: GenConfig) -> void:
	var rt := config.room_type_by_id(spec.type_id)
	var params: ScatterParams = null
	if rt != null:
		params = rt.generator_params as ScatterParams
	if params == null:
		return
	var count := params.count_per_slot * spec.size_slots.x * spec.size_slots.y
	var min_d2 := params.min_spacing * params.min_spacing
	var px := PackedInt32Array()
	var py := PackedInt32Array()
	for _n in count:
		for _a in ATTEMPTS_PER_BLOCKER:
			var x := rng.randi_range(1, w - 2)
			var y := rng.randi_range(1, h - 2)
			var idx := y * w + x
			if grid[idx] != RoomBuilder.FLOOR or protected[idx] == 1:
				continue
			var ok := true
			for i in px.size():
				var dx := px[i] - x
				var dy := py[i] - y
				if dx * dx + dy * dy < min_d2:
					ok = false
					break
			if ok:
				_grow_clump(grid, protected, w, h, rng, x, y,
						rng.randi_range(params.clump_min, params.clump_max))
				px.append(x)
				py.append(y)
				break


## Grow `size` blockers from a seed tile by random neighbour walk. Deterministic: same RNG
## stream + same (deterministic) grid. Only interior, unprotected FLOOR tiles join the clump.
static func _grow_clump(grid: PackedByteArray, protected: PackedByteArray, w: int, h: int,
		rng: RandomNumberGenerator, cx: int, cy: int, size: int) -> void:
	grid[cy * w + cx] = RoomBuilder.BLOCKER
	var tx := PackedInt32Array([cx])
	var ty := PackedInt32Array([cy])
	var attempts := size * 6
	while tx.size() < size and attempts > 0:
		attempts -= 1
		var i := rng.randi_range(0, tx.size() - 1)
		var nx := tx[i]
		var ny := ty[i]
		match rng.randi_range(0, 3):
			0: nx += 1
			1: nx -= 1
			2: ny += 1
			3: ny -= 1
		if nx < 1 or ny < 1 or nx > w - 2 or ny > h - 2:
			continue
		var nidx := ny * w + nx
		if grid[nidx] != RoomBuilder.FLOOR or protected[nidx] == 1:
			continue
		grid[nidx] = RoomBuilder.BLOCKER
		tx.append(nx)
		ty.append(ny)
