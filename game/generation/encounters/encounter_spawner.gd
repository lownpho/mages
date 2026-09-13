class_name EncounterSpawner
extends Node
## Streams WorldEncounters into the existing enemy scenes and keeps the Run's defeats. Generated
## identity is metadata on the root Creature; runtime summons and death splits bypass this spawner,
## carry no such metadata and are never recorded. A real death is recorded by member key; a creature
## freed any other way (its chunk unloading, a rebuild, a debug Clear) is not, so it returns at full
## health the next time its chunk loads.

@export var streamer: ChunkStreamer
@export var enemies_parent: Node2D

var world_encounters: WorldEncounters
var defeats := RunDefeats.new()
var _live: Dictionary[Vector2i, Array] = {}
var _scenes: Dictionary[StringName, PackedScene] = {}


func _ready() -> void:
	if streamer == null or enemies_parent == null:
		push_error("EncounterSpawner: streamer and enemies_parent must be wired")
		return
	streamer.chunk_loaded.connect(_on_chunk_loaded)
	streamer.chunk_unloaded.connect(_on_chunk_unloaded)


## Play time runs with the World: a paused tree stops it.
func _process(delta: float) -> void:
	defeats.play_time += delta


## Replaces generated data and respawns the chunks the tile streamer retained across a selective
## rebuild. The caller supplies the streamer's own interiors so tiles and encounters share caches.
## Keys follow place, so defeats carry over a rebuild; pass run_defeats to start a new Run's record.
## Retained chunks did not stream in, so their delayed deaths stay dead.
func build_world(encounter_data: WorldEncounters, run_defeats: RunDefeats = null) -> void:
	_clear_live()
	world_encounters = encounter_data
	if run_defeats != null:
		defeats = run_defeats
	if streamer != null:
		for coord in streamer.loaded_chunk_coords():
			_spawn_chunk(coord, false)


func live_member_keys() -> Array[String]:
	var out: Array[String] = []
	for enemy in live_members():
		out.append(enemy.get_meta("generated_key"))
	out.sort()
	return out


## The live generated enemies, without summons or splits.
func live_members() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for coord in _live:
		for enemy in _live[coord]:
			if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
				out.append(enemy)
	return out


func _on_chunk_loaded(coord: Vector2i) -> void:
	_spawn_chunk(coord, true)


func _spawn_chunk(coord: Vector2i, streamed_in: bool) -> void:
	if world_encounters == null or _live.has(coord):
		return
	var delay := world_encounters.graph.plan.content.curve.respawn_delay
	var spawned: Array[Node2D] = []
	for member in world_encounters.members_in_chunk(coord, streamer.chunk_tiles):
		if not defeats.admit(member, delay, streamed_in):
			continue
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
		if enemy.has_signal("died"):
			enemy.connect("died", defeats.record_death.bind(member))
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
