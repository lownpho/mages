extends Node
## Headless test that the title screen's backdrop is INERT. It runs the real generator, so the
## risk is not that it looks wrong — it is that it quietly behaves like a run: world.gd relays
## biome_entered onto GlobalEvent (which the bestiary writes to user://bestiary.cfg), emits
## world_ready (which the leaderboard reports to Talo as a run started), and calls
## GameState.persist() (which overwrites user://save.cfg). A backdrop doing any of that would
## corrupt a player's save and their stats just by them looking at the menu. Run:
##   godot --headless --path game res://tests/test_title_backdrop.tscn

const BACKDROP := preload("res://scenes/title_backdrop.tscn")
## A quarter of the drift circuit, to move the view without waiting real seconds.
const QUARTER_CIRCUIT := 15.0

var fails: Array[String] = []
# Members, not locals: a GDScript lambda captures locals BY VALUE, so a captured bool set inside
# the handler would only ever change the lambda's own copy and the assertion would never fire.
var saw_world_ready := false
var saw_biome: Array[String] = []


func _ready() -> void:
	GlobalEvent.world_ready.connect(func(_s: WorldStreamer) -> void: saw_world_ready = true)
	GlobalEvent.biome_entered.connect(func(b: StringName) -> void: saw_biome.append(String(b)))
	var before := {
		"save": _mtime(GameState.SAVE_PATH),
		"bestiary": _mtime(GlobalBestiary.SAVE_PATH),
		"had_save": GameState.has_save(),
		"seed": GameState.active_seed,
	}

	var backdrop: CanvasLayer = BACKDROP.instantiate()
	add_child(backdrop)
	for _i in 30:
		await get_tree().process_frame
	var streamer: WorldStreamer = backdrop.get_node("%Streamer")
	var start_offset := backdrop.offset
	backdrop._drift(QUARTER_CIRCUIT)
	await get_tree().process_frame

	# It has to be a REAL world, or the rest of this test proves nothing.
	if streamer.world_spec == null:
		fails.append("no world was generated")
	if streamer.loaded_chunks() <= 0:
		fails.append("no chunks streamed in, so nothing would be visible")
	if backdrop.offset == start_offset:
		fails.append("the view did not move: offset stayed %s" % start_offset)

	# Smoothness: ONE frame of drift must move the view. The drift is only a few px/second, so
	# snapping the offset to whole game pixels leaves it stationary for ~15 frames and then jumps a
	# full tile-pixel — the stutter this guards against. canvas_items stretch rasterises at window
	# resolution, so a fractional offset is real and lands on an exact device pixel.
	var before_frame := backdrop.offset
	backdrop._drift(1.0 / 60.0)
	if backdrop.offset == before_frame:
		fails.append("a single frame of drift moved nothing — is the offset being rounded?")

	# ...and it still must not have behaved like a run.
	if saw_world_ready:
		fails.append("emitted GlobalEvent.world_ready — the leaderboard books that as a run")
	if not saw_biome.is_empty():
		fails.append("emitted biome_entered %s — the bestiary persists visited biomes" % str(saw_biome))
	if _mtime(GameState.SAVE_PATH) != before["save"]:
		fails.append("user://save.cfg was written")
	if _mtime(GlobalBestiary.SAVE_PATH) != before["bestiary"]:
		fails.append("user://bestiary.cfg was written")
	if GameState.has_save() != before["had_save"]:
		fails.append("changed whether a save exists")
	if GameState.active_seed != before["seed"]:
		fails.append("took over the run's seed (active_seed %s -> %s)"
				% [before["seed"], GameState.active_seed])
	# No EntitySpawner is wired, so nothing should be alive in there.
	var creatures := _count_creatures(backdrop)
	if creatures > 0:
		fails.append("%d creature(s) spawned in the backdrop" % creatures)

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


func _mtime(path: String) -> int:
	return FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0


func _count_creatures(node: Node) -> int:
	var n := 1 if node is Creature else 0
	for child in node.get_children():
		n += _count_creatures(child)
	return n
