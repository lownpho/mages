class_name WgChunk
## One streaming chunk (spec §11 / godot_tips): a small Node2D owning its OWN TileMapLayers, fully
## populated by WorldStreamer BEFORE it enters the tree. Unloading is just queue_free() — O(1), no
## per-cell erase storm on a giant shared layer.
##
## Layers are built in code (not a .tscn) because chunks are procedural. A chunk may overlap more
## than one biome, and each biome has its OWN per-class tilesets, so a single shared TileMapLayer
## (which holds one tile_set) cannot serve both. Instead layers are created lazily per biome via
## layers_for(): one floor/wall/blocker/decor TileMapLayer group per biome present in the chunk,
## each backed by that biome's tileset (skipping null slots). Biome regions never share a cell, so
## cross-biome draw order is irrelevant; within a biome order is floor < wall < blocker < decor.
## Wall/blocker layers get physics_quadrant_size == chunk_tiles so the engine batches colliders.
extends Node2D

var chunk_coord: Vector2i
## Spawn entries overlapping this chunk, with a `world_tile` field resolved (Task 9: consumed
## by WgEntitySpawner via WorldStreamer.chunk_loaded).
var spawn_data: Array = []

var _quadrant: int = 16
var _biome_layers: Dictionary = {}   # StringName biome_id -> { "floor"/"wall"/"blocker"/"decor": TileMapLayer|null }


func setup(coord: Vector2i, origin_px: Vector2, quadrant: int) -> void:
	chunk_coord = coord
	position = origin_px
	_quadrant = quadrant


## The (up to four) TileMapLayers for one biome, created + cached on first request. Each slot is a
## TileMapLayer or null (when the presentation leaves that class's tileset unset). Order of
## add_child is floor < wall < blocker < decor so the decor overlay draws on top within a biome.
func layers_for(biome_id: StringName, pres: BiomePresentation) -> Dictionary:
	if _biome_layers.has(biome_id):
		return _biome_layers[biome_id]
	var group := {
		"floor": _make_layer("%s_floor" % biome_id, pres.floor_tileset, false),
		"wall": _make_layer("%s_wall" % biome_id, pres.wall_tileset, true),
		"blocker": _make_layer("%s_blocker" % biome_id, pres.blocker_tileset, true),
		"decor": _make_layer("%s_decor" % biome_id, pres.decor_tileset, false),
	}
	_biome_layers[biome_id] = group
	return group


func _make_layer(layer_name: String, tileset: TileSet, collides: bool) -> TileMapLayer:
	if tileset == null:
		return null
	var l := TileMapLayer.new()
	l.name = layer_name
	l.tile_set = tileset
	if collides:
		l.physics_quadrant_size = _quadrant
	add_child(l)
	return l


## Placeholder spawn marker (Task 8): a small coloured square at a chunk-local tile. Real enemy
## scenes are Task 9. `is_item` → gold, else red (enemy). Freed with the chunk.
func add_spawn_marker(local_tile: Vector2i, tile_px: int, is_item: bool) -> void:
	var m := Polygon2D.new()
	var s := float(tile_px)
	m.polygon = PackedVector2Array([Vector2(0, 0), Vector2(s, 0), Vector2(s, s), Vector2(0, s)])
	m.color = Color(0.95, 0.8, 0.2) if is_item else Color(0.9, 0.2, 0.2)
	m.position = Vector2(local_tile) * tile_px
	m.z_index = 50
	add_child(m)
