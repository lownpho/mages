extends Node
## Headless determinism test for the hash/seeding core (WorldHash). Pure logic, no scene
## tree touched. Run:
##   godot --headless --path game res://tests/generation/test_hash.tscn

const GAMMA := -7046029254386353131  # 0x9E3779B97F4A7C15 as signed-64 (GDScript clamps the raw hex)


func _ready() -> void:
	var fails: Array[String] = []

	# 1. SplitMix64 known-answer vectors. The reference SplitMix64 generator seeded to state 0
	# advances state by GAMMA before each finalize, so its Nth output is finalize(N*GAMMA).
	# WorldHash.splitmix64(x) adds GAMMA internally, so splitmix64(0), splitmix64(GAMMA),
	# splitmix64(2*GAMMA) reproduce outputs 1..3 of that reference sequence.
	var v0 := WorldHash.splitmix64(0)
	var v1 := WorldHash.splitmix64(GAMMA)
	var v2 := WorldHash.splitmix64(GAMMA * 2)
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
	var neg1 := WorldHash.splitmix64(-1)  # -1 == 0xFFFFFFFFFFFFFFFF unsigned
	var hb := WorldHash.splitmix64(-9223372036854775808)  # 0x8000000000000000
	print("high-bit inputs (expected -> computed):")
	print("  splitmix64(-1)     E4D971771B652C20 -> ", _hex(neg1))
	print("  splitmix64(hi-bit) 481EC0A212A9F3DB -> ", _hex(hb))
	if _hex(neg1) != "E4D971771B652C20":
		fails.append("splitmix64(-1) mismatch: " + _hex(neg1))
	if _hex(hb) != "481EC0A212A9F3DB":
		fails.append("splitmix64(hi-bit) mismatch: " + _hex(hb))

	# 3. threshold bounds: p=0 maps to 0 and p=1 to 2^32, above any u32 draw.
	if WorldHash.threshold(0.0) != 0:
		fails.append("threshold(0.0) != 0")
	if WorldHash.threshold(1.0) != 0x100000000:
		fails.append("threshold(1.0) != 2^32")

	# 4. unit_seed: the World generator's seed from World seed, namespace and place key.
	var unit := WorldHash.unit_seed(7, WorldHash.NS_ZONE_ORDER, "glade")
	if unit != WorldHash.unit_seed(7, WorldHash.NS_ZONE_ORDER, "glade"):
		fails.append("unit_seed not deterministic")
	for other in [WorldHash.unit_seed(8, WorldHash.NS_ZONE_ORDER, "glade"), WorldHash.unit_seed(7, WorldHash.NS_ATTACHMENTS, "glade"),
			WorldHash.unit_seed(7, WorldHash.NS_ZONE_ORDER, "deepwood"), WorldHash.unit_seed(7, WorldHash.NS_ZONE_ORDER, "")]:
		if other == unit:
			fails.append("unit_seed collided across seed, namespace or key")

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
