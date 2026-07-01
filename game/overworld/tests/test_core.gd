extends Node
## Headless determinism test for Group A core primitives (Hash, GenContext). Pure logic,
## no scene tree touched — safe to run with the editor open. Run:
##   godot --headless --path game overworld/tests/test_core.tscn


func _ready() -> void:
	var fails: Array[String] = []
	var seed := 12345

	# 1. Stable — same inputs give the same value across repeated calls.
	for i in 200:
		var x := (i * 7) - 40
		var y := (i * 13) - 70
		if Hash.value(seed, x, y, 0) != Hash.value(seed, x, y, 0):
			fails.append("value not stable at (%d,%d)" % [x, y])
			break

	# 2. Range — every value lands in [0, 1).
	for x in range(-50, 50):
		for y in range(-50, 50):
			var v := Hash.value(seed, x, y, 0)
			if v < 0.0 or v >= 1.0:
				fails.append("value out of [0,1): %f at (%d,%d)" % [v, x, y])
				break

	# 3. Channels decorrelate — channel 0 vs 1 on the same tiles should barely correlate
	# and rarely coincide. A stateless hash with per-channel mixing gives ~0 correlation.
	var n := 0
	var same := 0
	var sx := 0.0
	var sy := 0.0
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for x in range(0, 60):
		for y in range(0, 60):
			var a := Hash.value(seed, x, y, 0)
			var b := Hash.value(seed, x, y, 1)
			if a == b:
				same += 1
			sx += a; sy += b; sxy += a * b; sxx += a * a; syy += b * b
			n += 1
	var cov := sxy / n - (sx / n) * (sy / n)
	var std_a := sqrt(maxf(sxx / n - (sx / n) * (sx / n), 0.0))
	var std_b := sqrt(maxf(syy / n - (sy / n) * (sy / n), 0.0))
	var corr := cov / maxf(std_a * std_b, 1e-9)
	print("channel corr: %.4f   coincidences: %d/%d" % [corr, same, n])
	if abs(corr) > 0.1:
		fails.append("channels correlate (|corr|=%.3f)" % abs(corr))
	if same > n / 100:
		fails.append("channels coincide too often (%d/%d)" % [same, n])

	# 4. Snapshot a grid of hashes, then diff on a fresh recompute — must be identical.
	var snap_a := _snapshot(seed)
	var snap_b := _snapshot(seed)
	print("snapshot: %d cells, identical on recompute: %s" % [snap_a.size(), snap_a == snap_b])
	if snap_a.is_empty() or snap_a != snap_b:
		fails.append("hash grid not identical on recompute")
	# A different seed must actually change the grid.
	if _snapshot(seed) == _snapshot(seed + 1):
		fails.append("different seed produced identical grid")

	# 5. Derived helpers — chance / pick / range_i behave and stay in-bounds.
	var arr := ["a", "b", "c", "d"]
	for x in range(-30, 30):
		for y in range(-30, 30):
			if not (Hash.pick(seed, x, y, 2, arr) in arr):
				fails.append("pick returned non-member")
				break
			var r := Hash.range_i(seed, x, y, 3, 5, 9)
			if r < 5 or r > 9:
				fails.append("range_i out of [5,9]: %d" % r)
				break
	# chance(p) should fire at roughly rate p over many tiles.
	var hits := 0
	for x in range(0, 100):
		for y in range(0, 100):
			if Hash.chance(seed, x, y, 4, 0.3):
				hits += 1
	var rate := hits / 10000.0
	print("chance(0.3) observed rate: %.3f" % rate)
	if abs(rate - 0.3) > 0.03:
		fails.append("chance rate off: %.3f (expected ~0.30)" % rate)
	# range_i degenerate range clamps to lo.
	if Hash.range_i(seed, 1, 1, 5, 7, 7) != 7:
		fails.append("range_i(lo==hi) did not return lo")

	# 6. GenContext helpers — tile↔world round-trip and deterministic scatter within a tile.
	var ctx := GenContext.new()
	var px: int = GameConstants.PX_PER_TILE
	for t in [Vector2i(0, 0), Vector2i(3, -4), Vector2i(-7, 12)]:
		if ctx.world_to_tile(ctx.tile_to_world(t)) != t:
			fails.append("tile<->world round-trip failed at %s" % t)
		var s0 := ctx.scatter_pos(t, seed, 10, 11)
		if ctx.scatter_pos(t, seed, 10, 11) != s0:
			fails.append("scatter_pos not deterministic at %s" % t)
		# Scatter stays inside the tile's pixel cell (never leaks into a neighbour).
		if ctx.world_to_tile(s0) != t:
			fails.append("scatter_pos escaped its tile at %s (px=%d)" % [t, px])

	print("RESULT: ", "PASS" if fails.is_empty() else "FAIL " + str(fails))
	get_tree().quit(1 if not fails.is_empty() else 0)


# A grid of hashes across two channels, keyed by "x,y,ch" — stable strings so two
# snapshots compare by value.
func _snapshot(world_seed: int) -> Dictionary:
	var out := {}
	for x in range(-20, 20):
		for y in range(-20, 20):
			for ch in 2:
				out["%d,%d,%d" % [x, y, ch]] = Hash.value(world_seed, x, y, ch)
	return out
