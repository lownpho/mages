extends Node
## Headless determinism test for the hash/seeding core (WgHash). Pure logic, no scene
## tree touched. Run:
##   godot --headless --path game res://tests/worldgen/test_hash.tscn

const GAMMA := -7046029254386353131  # 0x9E3779B97F4A7C15 as signed-64 (GDScript clamps the raw hex)


func _ready() -> void:
	var fails: Array[String] = []

	# 1. SplitMix64 known-answer vectors. The reference SplitMix64 generator seeded to state 0
	# advances state by GAMMA before each finalize, so its Nth output is finalize(N*GAMMA).
	# WgHash.splitmix64(x) adds GAMMA internally, so splitmix64(0), splitmix64(GAMMA),
	# splitmix64(2*GAMMA) reproduce outputs 1..3 of that reference sequence.
	var v0 := WgHash.splitmix64(0)
	var v1 := WgHash.splitmix64(GAMMA)
	var v2 := WgHash.splitmix64(GAMMA * 2)
	print("SplitMix64 reference vectors (expected -> computed):")
	print("  [0]  E220A8397B1DCDAF -> ", _hex(v0))
	print("  [1]  6E789E6AA1B965F4 -> ", _hex(v1))
	print("  [2]  06C45D188009454F -> ", _hex(v2))
	if _hex(v0) != "E220A8397B1DCDAF":
		fails.append("splitmix64(0) mismatch: " + _hex(v0))
	if _hex(v1) != "6E789E6AA1B965F4":
		fails.append("splitmix64(GAMMA) mismatch: " + _hex(v1))
	if _hex(v2) != "06C45D188009454F":
		fails.append("splitmix64(2*GAMMA) mismatch: " + _hex(v2))

	# 2. Negative / high-bit inputs — catches the arithmetic-shift bug. Expected values were
	# computed with an independent unsigned-64 reference (Python).
	var neg1 := WgHash.splitmix64(-1)  # -1 == 0xFFFFFFFFFFFFFFFF unsigned
	var hb := WgHash.splitmix64(-9223372036854775808)  # 0x8000000000000000
	print("high-bit inputs (expected -> computed):")
	print("  splitmix64(-1)     E4D971771B652C20 -> ", _hex(neg1))
	print("  splitmix64(hi-bit) 481EC0A212A9F3DB -> ", _hex(hb))
	if _hex(neg1) != "E4D971771B652C20":
		fails.append("splitmix64(-1) mismatch: " + _hex(neg1))
	if _hex(hb) != "481EC0A212A9F3DB":
		fails.append("splitmix64(hi-bit) mismatch: " + _hex(hb))

	# 3. seed_for determinism.
	var gv := 1
	var cfg := 0
	var parts_a: Array[int] = [12345, WgHash.NS_ROOM_GRAPH, 3, 7]
	var parts_b: Array[int] = [12345, WgHash.NS_ROOM_GRAPH, 7, 3]  # permuted coords
	var s1 := WgHash.seed_for(gv, cfg, parts_a)
	var s2 := WgHash.seed_for(gv, cfg, parts_a)
	if s1 != s2:
		fails.append("seed_for not deterministic")
	if WgHash.seed_for(gv, cfg, parts_a) == WgHash.seed_for(gv, cfg, parts_b):
		fails.append("permuted parts collided")
	# Different namespace must diverge.
	var parts_ns: Array[int] = [12345, WgHash.NS_BORDER, 3, 7]
	if WgHash.seed_for(gv, cfg, parts_a) == WgHash.seed_for(gv, cfg, parts_ns):
		fails.append("different namespace collided")
	# Different config_hash must diverge.
	if WgHash.seed_for(gv, cfg, parts_a) == WgHash.seed_for(gv, 999, parts_a):
		fails.append("different config_hash collided")

	# 4. 10k seed_for outputs → no collisions (sanity, not proof).
	var seen := {}
	var collisions := 0
	for x in 100:
		for y in 100:
			var s := WgHash.seed_for(gv, cfg, [7, WgHash.NS_INTERIOR, x, y] as Array[int])
			if seen.has(s):
				collisions += 1
			seen[s] = true
	print("10k seed_for outputs, distinct: %d, collisions: %d" % [seen.size(), collisions])
	if collisions != 0:
		fails.append("seed_for collisions: %d" % collisions)

	# 5. threshold / chance sanity: p=1 always fires, p=0 never, p=0.3 ~ 0.3.
	if WgHash.threshold(0.0) != 0:
		fails.append("threshold(0.0) != 0")
	if WgHash.threshold(1.0) != 0x100000000:
		fails.append("threshold(1.0) != 2^32")
	var r0 := WgHash.rng(42)
	for i in 1000:
		if WgHash.chance(r0, WgHash.threshold(1.0)) == false:
			fails.append("chance(threshold 1.0) failed to fire")
			break
	var r1 := WgHash.rng(42)
	for i in 1000:
		if WgHash.chance(r1, WgHash.threshold(0.0)):
			fails.append("chance(threshold 0.0) fired")
			break
	var r2 := WgHash.rng(1234)
	var t30 := WgHash.threshold(0.3)
	var hits := 0
	for i in 20000:
		if WgHash.chance(r2, t30):
			hits += 1
	var rate := hits / 20000.0
	print("chance(0.3) observed rate: %.3f" % rate)
	if absf(rate - 0.3) > 0.02:
		fails.append("chance rate off: %.3f" % rate)

	if fails.is_empty():
		print("ALL PASS")
		get_tree().quit(0)
	else:
		for f in fails:
			print("  FAIL: ", f)
		print("FAILED: %d" % fails.size())
		get_tree().quit(1)


# Format a signed 64-bit int as uppercase 16-digit hex, interpreting it as unsigned. Avoids
# all signed-literal ambiguity when comparing against reference vectors.
func _hex(v: int) -> String:
	var s := String.num_uint64(v, 16).to_upper()
	while s.length() < 16:
		s = "0" + s
	return s
