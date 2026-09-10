extends Node
## Headless map-marker test: discovering the whole world drops one marker per room feature, at the
## feature's tile — fountains as MARKER_FOUNTAIN (any scene whose root is a Fountain, so a new
## fountain variant can't silently fall back to the door color) and every other feature (doors)
## as MARKER_FEATURE. Run:
##   godot --headless --path game res://tests/test_map_markers.tscn

const SEEDS := 3

var _is_fountain := {}   # PackedScene -> bool


func _ready() -> void:
	var fails: Array[String] = []
	var config: GenConfig = load("res://world_content/gen_config.tres")
	var fountains := 0
	var doors := 0

	for i in SEEDS:
		var seed_v := 15_485_863 * i + 7
		var streamer := WorldStreamer.new()
		streamer.config = config
		streamer.build_world(seed_v)
		var state := MapState.new()
		state.setup(streamer, MapState.ZOOM_TILES_PER_PX)

		var ss := config.room_slot_tiles
		for ty in range(0, state.world_tiles.y, ss):
			for tx in range(0, state.world_tiles.x, ss):
				state.discover_at(Vector2i(tx, ty))

		var expected: Array = []
		for slot: Vector2i in state.discovered:
			var room := streamer.get_room_output(streamer.room_spec_at_tile(slot.x * ss, slot.y * ss))
			for sp in room.spawns:
				if sp is Dictionary and sp.has("feature"):
					var t: Vector2i = sp.get("tile", Vector2i.ZERO)
					var kind := MapState.MARKER_FOUNTAIN if _fountain(sp["feature"]) \
							else MapState.MARKER_FEATURE
					expected.append({"tile": slot * ss + t, "kind": kind})
		var actual := state.markers.filter(func(m): return m["kind"] != MapState.MARKER_BOSS)

		for m in expected:
			if m["kind"] == MapState.MARKER_FOUNTAIN:
				fountains += 1
			else:
				doors += 1
			var idx := actual.find(m)
			if idx < 0:
				fails.append("seed %d: missing %s marker at %s" % [seed_v, _name(m["kind"]), m["tile"]])
			else:
				actual.remove_at(idx)
		for m in actual:
			fails.append("seed %d: stray %s marker at %s" % [seed_v, _name(m["kind"]), m["tile"]])

	if fountains == 0:
		fails.append("no fountain markers across %d seeds" % SEEDS)
	if doors == 0:
		fails.append("no door/feature markers across %d seeds" % SEEDS)

	if fails.is_empty():
		print("ALL PASS (%d fountain, %d feature markers)" % [fountains, doors])
	else:
		for f in fails:
			print("  - ", f)
		print("FAILED: %d" % fails.size())
	get_tree().quit()


func _fountain(scene: PackedScene) -> bool:
	if not _is_fountain.has(scene):
		var n := scene.instantiate()
		_is_fountain[scene] = n is Fountain
		n.free()
	return _is_fountain[scene]


static func _name(kind: int) -> String:
	return "fountain" if kind == MapState.MARKER_FOUNTAIN else "feature"
