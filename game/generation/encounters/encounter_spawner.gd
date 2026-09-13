class_name EncounterSpawner
extends Node
## Streams WorldEncounters into the existing enemy scenes. Generated identity is metadata on the
## root Creature; runtime summons and death splits bypass this spawner and have no such metadata.

@export var streamer: ChunkStreamer
@export var enemies_parent: Node2D

var world_encounters: WorldEncounters
var _live: Dictionary[Vector2i, Array] = {}
var _scenes: Dictionary[StringName, PackedScene] = {}


func _ready() -> void:
	if streamer == null or enemies_parent == null:
		push_error("EncounterSpawner: streamer and enemies_parent must be wired")
		return
	streamer.chunk_loaded.connect(_on_chunk_loaded)
	streamer.chunk_unloaded.connect(_on_chunk_unloaded)


## Replaces generated data and respawns the chunks the tile streamer retained across a selective
## rebuild. The caller supplies the streamer's own interiors so tiles and encounters share caches.
func build_world(encounter_data: WorldEncounters) -> void:
	_clear_live()
	world_encounters = encounter_data
	if streamer != null:
		for coord in streamer.loaded_chunk_coords():
			_on_chunk_loaded(coord)


func live_member_keys() -> Array[String]:
	var out: Array[String] = []
	for coord in _live:
		for enemy in _live[coord]:
			if is_instance_valid(enemy):
				out.append(enemy.get_meta("generated_key"))
	out.sort()
	return out


func _on_chunk_loaded(coord: Vector2i) -> void:
	if world_encounters == null or _live.has(coord):
		return
	var spawned: Array[Node2D] = []
	for member in world_encounters.members_in_chunk(coord, streamer.chunk_tiles):
		var scene := _scene_for(member.enemy)
		if scene == null:
			continue
		var enemy := scene.instantiate() as Node2D
		if enemy == null:
			continue
		enemy.position = (Vector2(member.tile) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
		enemy.set_meta("generated_key", member.key)
		enemy.set_meta("encounter_key", member.encounter_key)
		enemy.set_meta("room_key", member.room_key)
		enemy.set_meta("encounter_leader", member.leader)
		enemies_parent.add_child(enemy)
		spawned.append(enemy)
	if not spawned.is_empty():
		_live[coord] = spawned


func _on_chunk_unloaded(coord: Vector2i) -> void:
	if not _live.has(coord):
		return
	for enemy in _live[coord]:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_live.erase(coord)


func _scene_for(enemy: CreatureResource) -> PackedScene:
	var id := StringName(enemy.resource_path.get_base_dir().get_file())
	if _scenes.has(id):
		return _scenes[id]
	var path := "%s/%s.tscn" % [enemy.resource_path.get_base_dir(), id]
	var scene := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if scene == null:
		push_warning("EncounterSpawner: no scene for %s at %s" % [id, path])
	_scenes[id] = scene
	return scene


func _clear_live() -> void:
	for coord in _live:
		for enemy in _live[coord]:
			if is_instance_valid(enemy):
				enemy.queue_free()
	_live.clear()
