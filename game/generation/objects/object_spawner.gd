class_name ObjectSpawner
extends Node
## Streams WorldObjects into their scenes, keeps the Run's Object state and carries travellers
## through Portals. Each planned Object is instantiated once while its chunk is loaded, at its
## spot, tagged with its key as generated_key metadata and configured by setup(data); unloading
## frees it.
##
## Objects own small state dictionaries keyed by their generated place: data.state is the Object's
## entry in states, which outlives the scene, so whatever a reactive NPC writes there is restored on
## its next setup, after its chunk reloads or a rebuild. A Professor writes there once it has given
## what a finished Bestiary page earned, so the gift comes once a Run and a portal it opened stands
## again when its chunk returns. Fountains and Signs write nothing: a fountain's cooldown resets when
## its chunk reloads, and a Sign's reveal belongs to the Map.
##
## A Portal's traveller lands on its landing tile, keeping its facing, and the streamer loads the
## destination at once, as it does for a teleport. Every Warp leaves Blink's flash at both ends.

signal warped(body: Node2D, destination_room: String)

## Blink's afterimage, left at both ends of a Warp. It owns itself: the animation frees the node.
const POOF_SCENE := preload("res://characters/player/spells/blink/poof.tscn")

@export var streamer: ChunkStreamer
@export var objects_parent: Node2D

var world_objects: WorldObjects
## Object key -> its state. Objects that never wrote keep an empty entry, which saved_states omits.
var states: Dictionary[String, Dictionary] = {}
var _live: Dictionary[Vector2i, Array] = {}


func _ready() -> void:
	if streamer == null or objects_parent == null:
		push_error("ObjectSpawner: streamer and objects_parent must be wired")
		return
	streamer.chunk_loaded.connect(_on_chunk_loaded)
	streamer.chunk_unloaded.connect(_on_chunk_unloaded)


## Replaces generated data and respawns the Objects of chunks the streamer retained. Keys follow
## place, so state carries over a rebuild; a new Run starts without any.
func build_world(object_data: WorldObjects, new_run := false) -> void:
	_clear_live()
	world_objects = object_data
	if new_run:
		states.clear()
	if streamer != null:
		for coord in streamer.loaded_chunk_coords():
			_on_chunk_loaded(coord)


## A copy of every non-empty Object state, for the Run save.
func saved_states() -> Dictionary[String, Dictionary]:
	var out: Dictionary[String, Dictionary] = {}
	for key in states:
		if not states[key].is_empty():
			out[key] = states[key].duplicate(true)
	return out


## Replaces Object state with a saved Run's, before build_world spawns anything: Objects already
## live keep the state they were set up with.
func restore_states(saved: Dictionary) -> void:
	states.clear()
	for key: String in saved:
		states[key] = (saved[key] as Dictionary).duplicate(true)


## The live Objects, in no particular order.
func live_objects() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for coord in _live:
		for node in _live[coord]:
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				out.append(node)
	return out


func _on_chunk_loaded(coord: Vector2i) -> void:
	if world_objects == null or _live.has(coord):
		return
	var spawned: Array[Node2D] = []
	for site in world_objects.in_chunk(coord, streamer.chunk_tiles):
		var scene := world_objects.scene_for(site)
		if scene == null:
			continue
		var node := scene.instantiate() as Node2D
		if node == null:
			continue
		node.position = (Vector2(site.spot) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
		node.set_meta("generated_key", site.key)
		if node.has_method("setup"):
			var data := world_objects.setup_data(site)
			data.state = states.get_or_add(site.key, {})
			node.call("setup", data)
		if node.has_signal("warp_entered"):
			node.connect("warp_entered", _on_warp_entered)
		objects_parent.add_child(node)
		spawned.append(node)
	if not spawned.is_empty():
		_live[coord] = spawned


func _on_chunk_unloaded(coord: Vector2i) -> void:
	if not _live.has(coord):
		return
	for node in _live[coord]:
		if is_instance_valid(node):
			node.queue_free()
	_live.erase(coord)


## Portals report from inside the physics step, where streaming can't add Objects or enemies.
func _on_warp_entered(body: Node2D, destination_room: String, landing: Vector2i) -> void:
	_warp.call_deferred(body, destination_room, landing)


## Public seam for a warp the Map drives (a Fountain recall): land `body` on `tile`, streaming the
## destination in. The Door/Portal path reports through `warp_entered`; this one is already out of
## the physics step, so it runs at once.
func warp_to(body: Node2D, tile: Vector2i) -> void:
	_warp(body, "", tile)


func _warp(body: Node2D, destination_room: String, landing: Vector2i) -> void:
	if not is_instance_valid(body):
		return
	var from := body.global_position
	body.global_position = (Vector2(landing) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
	_poof(from)
	_poof(body.global_position)
	# Arrival is itself entry; record it synchronously instead of waiting for GlobalMap's next
	# movement poll (which also makes a paused/debug-driven Warp discover the destination).
	GlobalMap.discover_at(landing)
	if streamer != null and streamer.graph != null and streamer.target != null:
		streamer.prepare()
	warped.emit(body, destination_room)


## The blink flash at `at`, under the same parent as the Objects. Frees itself when the effect ends.
func _poof(at: Vector2) -> void:
	if objects_parent == null:
		return
	var poof := POOF_SCENE.instantiate() as AnimatedSprite2D
	objects_parent.add_child(poof)
	poof.global_position = at
	poof.animation_finished.connect(poof.queue_free)
	poof.play()


func _clear_live() -> void:
	for coord in _live:
		for node in _live[coord]:
			if is_instance_valid(node):
				node.queue_free()
	_live.clear()
