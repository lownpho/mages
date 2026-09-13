class_name WgChunk
## One streaming chunk: a small Node2D owning its OWN TileMapLayers, fully
## populated by WorldStreamer BEFORE it enters the tree. Unloading is just queue_free() — O(1), no
## per-cell erase storm on a giant shared layer.
##
## Layers are built in code (not a .tscn) because chunks are procedural. A chunk may overlap more
## than one biome, and each biome has its OWN per-class tilesets, so a single shared TileMapLayer
## (which holds one tile_set) cannot serve both. Instead layers are created lazily per biome via
## layers_for(): one floor/wall/rock/decoration TileMapLayer group per biome present in the
## chunk, each backed by that biome's tileset (skipping null slots), plus a decoration layer per
## Zone that overrides its Biome's decoration tileset. Biome regions never share a cell, so
## cross-biome draw order is irrelevant; within a biome order is floor < decoration < wall/rock.
## Wall/rock layers get physics_quadrant_size == chunk_tiles so the engine batches colliders.
extends Node2D

var chunk_coord: Vector2i
## Spawn entries overlapping this chunk, with a `world_tile` field resolved (consumed
## by WgEntitySpawner via WorldStreamer.chunk_loaded).
var spawn_data: Array = []

var _quadrant: int = 16
var _biome_layers: Dictionary = {}   # StringName biome_id -> { "floor"/"wall"/"rock"/"decoration": TileMapLayer|null }
var _zone_layers: Dictionary = {}    # StringName "<biome>/<zone>" -> decoration TileMapLayer


## Z-bands: floor/object_bg sit BEHIND every entity (flat ground), trees share the entity band (0)
## so they Y-sort against the player/enemies. y_sort_enabled here propagates the tree layers'
## per-tile sort up to the world's shared Y-sort root (World → WorldRoot → WorldStreamer → chunk →
## layer).
const _Z_FLOOR := -2
const _Z_OBJECT_BG := -1
const _Z_OBJECT := 0


func setup(coord: Vector2i, origin_px: Vector2, quadrant: int) -> void:
	chunk_coord = coord
	position = origin_px
	_quadrant = quadrant
	y_sort_enabled = true


## The (up to four) TileMapLayers for one biome, created + cached on first request. Each slot is a
## TileMapLayer or null (when the presentation leaves that layer's tileset unset).
func layers_for(biome_id: StringName, pres: BiomePresentation) -> Dictionary:
	for kind: StringName in [&"floor", &"wall", &"rock", &"decoration"]:
		layer_for(biome_id, pres, kind)
	return _biome_layers[biome_id]


## One of a biome's four layers (&"floor", &"wall", &"rock" or &"decoration"), created on first
## request; null when the presentation leaves its tileset unset.
func layer_for(biome_id: StringName, pres: BiomePresentation, kind: StringName) -> TileMapLayer:
	var group: Dictionary = _biome_layers.get_or_add(biome_id, {})
	if not group.has(kind):
		match kind:
			&"floor":
				group[kind] = _make_layer("%s_floor" % biome_id, pres.floor_tileset, _Z_FLOOR, false)
			&"wall":
				group[kind] = _make_layer("%s_wall" % biome_id, pres.wall_tileset, _Z_OBJECT, true)
			&"rock":
				group[kind] = _make_layer("%s_rock" % biome_id, pres.rock_tileset, _Z_OBJECT, true)
			_:
				group[kind] = _make_layer("%s_decoration" % biome_id, pres.decoration_tileset, _Z_OBJECT_BG, false)
	return group[kind]


## A flat decoration layer for a Zone that overrides its Biome's decoration tileset, keyed by
## "<biome>/<zone>"; created on first request.
func decoration_layer(key: StringName, tileset: TileSet) -> TileMapLayer:
	if not _zone_layers.has(key):
		_zone_layers[key] = _make_layer("%s_decoration" % String(key).replace("/", "_"), tileset, _Z_OBJECT_BG, false)
	return _zone_layers[key]


## `solid` layers (trees) collide AND Y-sort so tall props render in front/behind by base position;
## flat layers (floor/object_bg) do neither and are pinned to a background z-band.
func _make_layer(layer_name: String, tileset: TileSet, z: int, solid: bool) -> TileMapLayer:
	if tileset == null:
		return null
	var l := TileMapLayer.new()
	l.name = layer_name
	l.tile_set = tileset
	l.z_index = z
	if solid:
		l.physics_quadrant_size = _quadrant
		l.y_sort_enabled = true
	add_child(l)
	return l


## Placeholder spawn marker: a small coloured square at a chunk-local tile (real enemy scenes
## are spawned by WgEntitySpawner). `is_item` → gold, else red (enemy). Freed with the chunk.
func add_spawn_marker(local_tile: Vector2i, tile_px: int, is_item: bool) -> void:
	var m := Polygon2D.new()
	var s := float(tile_px)
	m.polygon = PackedVector2Array([Vector2(0, 0), Vector2(s, 0), Vector2(s, s), Vector2(0, s)])
	m.color = Color(0.95, 0.8, 0.2) if is_item else Color(0.9, 0.2, 0.2)
	m.position = Vector2(local_tile) * tile_px
	m.z_index = 50
	add_child(m)
