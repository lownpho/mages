class_name WgEntitySpawner
## Task 9: turns chunk spawn DATA into live enemy scenes. Chunks near the player instantiate
## their enemies on chunk_loaded; chunk_unloaded frees them (their spawn data regenerates
## identically, so walking away and back restores the same enemies in the same places — minus
## ones defeated this session). Defeated tracking is keyed by stable entity_id (spec §4.5);
## the save-delta system itself is out of scope, so the set lives for this session only.
extends Node

# Wired in the scene, or injected directly by code before add_child (tests build the rig by hand).
@export var streamer: WorldStreamer = null          ## the WorldStreamer to follow
@export var enemies_parent: Node2D = null           ## y-sorted parent the enemy scenes are added under

var defeated: Dictionary = {}        ## entity_id -> true (session-only)

var _live: Dictionary = {}           # chunk coord -> Array of enemy nodes
var _scenes: Dictionary = {}         # enemy_id -> PackedScene (or null when missing)


func _ready() -> void:
	if streamer == null or enemies_parent == null:
		push_error("WgEntitySpawner: streamer and enemies_parent must be wired (inspector or code)")
		return
	streamer.chunk_loaded.connect(_on_chunk_loaded)
	streamer.chunk_unloaded.connect(_on_chunk_unloaded)


## Entity ids of currently live enemies, sorted (test hook — deterministic to compare).
func live_entity_ids() -> Array:
	var out: Array = []
	for coord in _live:
		for e in _live[coord]:
			if is_instance_valid(e):
				out.append(e.get_meta("entity_id"))
	out.sort()
	return out


func _on_chunk_loaded(coord: Vector2i, spawns: Array) -> void:
	var nodes: Array = []
	for sp in spawns:
		if sp.has("item_id"):
			continue   # loot on the ground arrives with real item content (Task 10)
		var eid: int = sp.get("entity_id", 0)
		if defeated.has(eid):
			continue
		var scene := _scene_for(sp.get("enemy_id", &""))
		if scene == null:
			continue
		var e: Node2D = scene.instantiate()
		e.position = (Vector2(sp["world_tile"]) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
		e.set_meta("entity_id", eid)
		e.tree_exiting.connect(_on_enemy_exiting.bind(e, eid))
		enemies_parent.add_child(e)
		nodes.append(e)
	if not nodes.is_empty():
		_live[coord] = nodes


func _on_chunk_unloaded(coord: Vector2i) -> void:
	if not _live.has(coord):
		return
	for e in _live[coord]:
		if is_instance_valid(e):
			e.set_meta("despawning", true)
			e.queue_free()
	_live.erase(coord)


## An enemy leaving the tree WITHOUT our despawn mark and at ≤ 0 health died for real —
## remember its entity_id so it stays dead for the rest of the session.
func _on_enemy_exiting(e: Node, eid: int) -> void:
	if e.has_meta("despawning"):
		return
	if "health" in e and e.health <= 0:
		defeated[eid] = true


func _scene_for(enemy_id: StringName) -> PackedScene:
	if _scenes.has(enemy_id):
		return _scenes[enemy_id]
	var path := "res://characters/enemies/%s/%s.tscn" % [enemy_id, enemy_id]
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = load(path)
	else:
		push_warning("WgEntitySpawner: no scene for enemy id '%s' (%s)" % [enemy_id, path])
	_scenes[enemy_id] = scene
	return scene
