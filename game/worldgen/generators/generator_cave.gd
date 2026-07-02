class_name RoomGenCave
## Cellular-automata cave generator (spec §8.2): seed wall noise at `fill_prob`, smooth with
## the 4-5 rule, write the result as WALL. PROTECTED tiles are forced floor every iteration,
## so the corridor star always pierces the cave and openings stay connected.
extends RoomGenBase


func run(grid: PackedByteArray, protected: PackedByteArray, w: int, h: int,
		rng: RandomNumberGenerator, spec: RoomSpec, config: GenConfig) -> void:
	var rt := config.room_type_by_id(spec.type_id)
	var params: CaveParams = null
	if rt != null:
		params = rt.generator_params as CaveParams
	var fill_prob := params.fill_prob if params != null else 0.45
	var iterations := params.iterations if params != null else 4
	var th := WgHash.threshold(fill_prob)

	var size := w * h
	var cur := PackedByteArray()
	cur.resize(size)
	# The perimeter is marked wall in the buffer (not written to the grid — the shell already
	# owns it) so the neighbor count below needs no bounds checks.
	for x in w:
		cur[x] = 1
		cur[(h - 1) * w + x] = 1
	for y in h:
		cur[y * w] = 1
		cur[y * w + w - 1] = 1
	# rng.randi() < th inlined (== WgHash.chance) — call overhead matters at tile scale.
	for y in range(1, h - 1):
		var row := y * w
		for x in range(1, w - 1):
			var idx := row + x
			if protected[idx] == 0 and rng.randi() < th:
				cur[idx] = 1

	var next := cur.duplicate()   # keeps the perimeter 1s; interior fully rewritten below
	for _it in iterations:
		for y in range(1, h - 1):
			var row := y * w
			for x in range(1, w - 1):
				var idx := row + x
				if protected[idx] == 1:
					next[idx] = 0
					continue
				var cnt: int = cur[idx - w - 1] + cur[idx - w] + cur[idx - w + 1] \
						+ cur[idx - 1] + cur[idx + 1] \
						+ cur[idx + w - 1] + cur[idx + w] + cur[idx + w + 1]
				next[idx] = 1 if (cnt >= 5 or (cnt == 4 and cur[idx] == 1)) else 0
		var tmp := cur
		cur = next
		next = tmp

	# `write_blockers` renders the cave mass as trees/rocks (BLOCKER) instead of cliff WALL —
	# same shape, different art class (e.g. deepwood tree-walls).
	var out_class := RoomBuilder.BLOCKER if params != null and params.write_blockers else RoomBuilder.WALL
	for y in range(1, h - 1):
		var row := y * w
		for x in range(1, w - 1):
			if cur[row + x] == 1:
				grid[row + x] = out_class
