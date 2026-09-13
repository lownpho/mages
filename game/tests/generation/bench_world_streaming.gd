extends Node
## Streaming benchmark, outside the test suite: walks a target at the player's walking speed along
## the shipped World's Ideal path, one simulated 60 fps frame per engine frame, with ChunkStreamer
## following it under a 320x180 camera. It records the streaming work in every frame and whether any
## chunk overlapping the view wasn't loaded yet. It fails when a frame's work passes the headless
## desktop threshold, a third of the 2 ms web budget, or a chunk came into view unready. Run by hand,
## alone:
##   godot --headless --path game res://tests/generation/bench_world_streaming.tscn -- [seeds] [seconds per seed]
## Results are recorded in .scratch/worldgen-rewrite-build/issues/04-walk-streamed-rendered-world.md.

const SHIPPED := "res://generation/world/"
const THRESHOLD_USEC := 2000.0 / 3.0
## The player's base_speed, in pixels per second.
const WALK_SPEED := 80.0
const FRAME := 1.0 / 60.0
const VIEW := Vector2(320, 180)

var _content: WorldContent
var _seeds := 3
var _seconds := 120.0
var _seed_index := 0
var _streamer: ChunkStreamer
var _target: Node2D
var _waypoints: Array[Vector2] = []
var _next_waypoint := 0
var _frame := 0
var _work: Array[int] = []
## Per frame, whether a chunk entered the tree.
var _entered: Array[bool] = []
var _unready: Dictionary[String, bool] = {}
var _loads := 0
var _over_shown := 0
var _loads_seen := 0
var _walked := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		_seeds = args[0].to_int()
	if args.size() > 1 and args[1].is_valid_float():
		_seconds = args[1].to_float()
	# A headless run can't draw, so it sleeps between frames unless told not to.
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	OS.low_processor_usage_mode_sleep_usec = 0
	# The game's 320x180 view, whatever size the headless window reports.
	get_window().size = Vector2i(1920, 1080)
	process_priority = -100
	_content = ContentLoader.load_content(SHIPPED)
	if not _content.is_valid():
		print(_content.report())
		get_tree().quit(1)
		return
	print("Streaming bench: %s, %d seeds, %.0f s walked each at %.0f px/s, Godot %s headless" % [SHIPPED, _seeds, _seconds,
			WALK_SPEED, Engine.get_version_info().string])
	_start_seed()


func _start_seed() -> void:
	var world_seed := 1000 + _seed_index * 7919
	var graph := WorldGraph.build(WorldPlanner.plan(_content, world_seed))
	if _streamer != null:
		_streamer.queue_free()
		_target.queue_free()
	_streamer = ChunkStreamer.new()
	add_child(_streamer)
	_target = Node2D.new()
	var camera := Camera2D.new()
	_target.add_child(camera)
	add_child(_target)
	camera.make_current()
	_streamer.build_world(graph)
	_waypoints.clear()
	var route := graph.plan.ideal_route()
	for n in route.size():
		var room := graph.rooms[route[n].key]
		_waypoints.append(_pixels(graph.tile_of(room.seed)))
		if n + 1 < route.size():
			_waypoints.append(_pixels(graph.passages[RoomPassage.pair(route[n].key, route[n + 1].key)].spot))
	_target.global_position = _waypoints[0]
	_next_waypoint = 1
	_frame = 0
	_streamer.target = _target
	var started := Time.get_ticks_usec()
	_streamer.prepare()
	print("  seed %d: viewport %s, %d chunks prepared at the spawn in %.0f ms" % [world_seed, get_viewport().get_visible_rect().size,
			_streamer.loaded_chunks(), (Time.get_ticks_usec() - started) / 1000.0])
	_streamer.chunk_loaded.connect(func(_coord: Vector2i) -> void: _loads += 1)


func _process(_delta: float) -> void:
	if _streamer == null or _streamer.graph == null:
		return
	if _frame > 0:
		_work.append(_streamer.last_work_usec)
		if _streamer.last_work_usec > THRESHOLD_USEC and _over_shown < 12:
			_over_shown += 1
			print("    frame %d over: %.3f ms = replan %d + free %d + queue %d + ahead %d usec" % ([_frame - 1,
					_streamer.last_work_usec / 1000.0] + Array(_streamer.last_work_split)))
		_entered.append(_loads != _loads_seen)
		_check_view()
	_loads_seen = _loads
	_frame += 1
	if _frame > int(_seconds / FRAME) or _next_waypoint >= _waypoints.size():
		print("    walked %.0f tiles in %d frames, %d chunks in view before they were ready so far" % [
				_frame * WALK_SPEED * FRAME / GameConstants.PX_PER_TILE, _frame, _unready.size()])
		_seed_index += 1
		if _seed_index >= _seeds:
			_finish()
		else:
			_start_seed()
		return
	var step := WALK_SPEED * FRAME
	_walked += step
	while step > 0.0 and _next_waypoint < _waypoints.size():
		var to := _waypoints[_next_waypoint]
		var distance := _target.global_position.distance_to(to)
		if distance <= step:
			_target.global_position = to
			step -= distance
			_next_waypoint += 1
		else:
			_target.global_position = _target.global_position.move_toward(to, step)
			step = 0.0


## Every chunk overlapping the view around the target must be loaded.
func _check_view() -> void:
	var first := _streamer.chunk_of(_target.global_position - VIEW * 0.5)
	var last := _streamer.chunk_of(_target.global_position + VIEW * 0.5 - Vector2.ONE * 0.01)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var key := "%d:%d,%d" % [_seed_index, x, y]
			if not _streamer.is_chunk_loaded(Vector2i(x, y)) and not _unready.has(key):
				_unready[key] = true
				if _unready.size() <= 8:
					print("    frame %d: chunk %d,%d in view unready at tile %s, %d queued, %d loaded" % [_frame, x, y,
							Vector2i((_target.global_position / GameConstants.PX_PER_TILE).floor()), _streamer.queued_chunks(), _streamer.loaded_chunks()])


func _finish() -> void:
	var sorted := _work.duplicate()
	sorted.sort()
	var over := sorted.filter(func(usec: int) -> bool: return usec > THRESHOLD_USEC).size()
	var over_entering := 0
	for n in _work.size():
		if _work[n] > THRESHOLD_USEC and _entered[n]:
			over_entering += 1
	var busy := sorted.filter(func(usec: int) -> bool: return usec > 0).size()
	print("  %d frames, %.0f tiles walked, %d chunks loaded while walking, %d frames with work" % [_work.size(),
			_walked / GameConstants.PX_PER_TILE, _loads, busy])
	print("  work per frame: median %.3f ms, p95 %.3f ms, p99 %.3f ms, max %.3f ms (threshold %.3f ms)" % [
			_at(sorted, 0.5), _at(sorted, 0.95), _at(sorted, 0.99), sorted[-1] / 1000.0, THRESHOLD_USEC / 1000.0])
	print("  frames over the threshold: %d (%d entering a chunk); chunks in view before they were ready: %d %s" % [over, over_entering,
			_unready.size(), _unready.keys().slice(0, 5)])
	var passed := over == 0 and _unready.is_empty() and not _work.is_empty()
	print("PASS" if passed else "FAIL")
	get_tree().quit(0 if passed else 1)


static func _at(sorted: Array[int], share: float) -> float:
	return sorted[mini(sorted.size() - 1, int(sorted.size() * share))] / 1000.0


static func _pixels(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
