extends Node
## Headless test that the title screen's backdrop waits for its World plan behind its fade-in and is
## INERT. It runs the real generator, so the risk is not that it looks wrong — it is that it quietly
## behaves like a Run: spawning enemies or Objects, building the Map, or saving (which would
## overwrite user://save.cfg). A backdrop doing any of that would corrupt a player's save just by
## them looking at the menu. Run:
##   godot --headless --path game res://tests/test_title_backdrop.tscn

const BACKDROP := preload("res://scenes/title_backdrop.tscn")
## A quarter of the drift circuit, to move the view without waiting real seconds.
const QUARTER_CIRCUIT := 15.0

var fails: Array[String] = []


func _ready() -> void:
	var before := {
		"save": _mtime(GameState.save_path),
		"bestiary": _mtime(GlobalBestiary.SAVE_PATH),
		"grimoire": _mtime(GlobalGrimoire.SAVE_PATH),
		"had_save": GameState.has_save(),
		"seed": GameState.active_seed,
	}

	var backdrop: CanvasLayer = BACKDROP.instantiate()
	add_child(backdrop)
	var world: Node2D = backdrop.get_node("World")
	var streamer: ChunkStreamer = backdrop.get_node("%Streamer")
	if backdrop.graph != null or world.modulate.a != 0.0:
		fails.append("the backdrop showed or planned before its first frame")
	await backdrop.planned
	if backdrop.graph == null or streamer.graph != backdrop.graph:
		fails.append("no World was planned and streamed")
	if streamer.loaded_chunks() <= 0:
		fails.append("no chunks streamed in, so nothing would be visible")
	# The spawn's view is ready before the fade reveals it.
	var view := Rect2(streamer.spawn_position() - get_viewport().get_visible_rect().size * 0.5,
			get_viewport().get_visible_rect().size)
	var first := streamer.chunk_of(view.position)
	var last := streamer.chunk_of(view.end - Vector2.ONE)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			if not streamer.is_chunk_loaded(Vector2i(x, y)):
				fails.append("chunk %d,%d in view wasn't ready as the backdrop faded in" % [x, y])
	await get_tree().create_timer(backdrop.FADE_SECONDS + 0.1).timeout
	if world.modulate.a < 1.0:
		fails.append("the backdrop never finished fading in (alpha %.2f)" % world.modulate.a)

	var start_offset := backdrop.offset
	backdrop._drift(QUARTER_CIRCUIT)
	await get_tree().process_frame
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

	# ...and it still must not have behaved like a Run.
	if GlobalMap.active != null:
		fails.append("built a Map — that books this as a real Run")
	if _mtime(GameState.save_path) != before["save"]:
		fails.append("user://save.cfg was written")
	if _mtime(GlobalBestiary.SAVE_PATH) != before["bestiary"]:
		fails.append("user://bestiary.cfg was written")
	if _mtime(GlobalGrimoire.SAVE_PATH) != before["grimoire"]:
		fails.append("user://grimoire.cfg was written")
	if GameState.has_save() != before["had_save"]:
		fails.append("changed whether a save exists")
	if GameState.active_seed != before["seed"]:
		fails.append("took over the run's seed (active_seed %s -> %s)"
				% [before["seed"], GameState.active_seed])
	# No spawners are wired, so nothing should be alive in there.
	var creatures := _count(backdrop, func(node: Node) -> bool: return node is Creature)
	var objects := _count(backdrop, func(node: Node) -> bool: return node.has_meta("generated_key"))
	if creatures > 0 or objects > 0:
		fails.append("%d creature(s) and %d Object(s) spawned in the backdrop" % [creatures, objects])

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


func _mtime(path: String) -> int:
	return FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0


func _count(node: Node, matches: Callable) -> int:
	var n := 1 if matches.call(node) else 0
	for child in node.get_children():
		n += _count(child, matches)
	return n
