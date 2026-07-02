class_name WgChunk
## One streaming chunk (spec §11 / godot_tips): a small Node2D owning its OWN ground/wall/decor
## TileMapLayer trio, fully populated by WorldStreamer BEFORE it enters the tree. Unloading is
## just queue_free() — O(1), no per-cell erase storm on a giant shared layer.
##
## Layers and tilesets are built in code (not a .tscn) because chunks are procedural — there is
## no authorable scene per chunk. Ground and wall share `floor_tileset` (grass tiles have no
## collider, wall tiles do); decor uses `object_tileset`. The wall/decor layers get
## physics_quadrant_size == CHUNK_SIZE so the engine batches their colliders per chunk.
extends Node2D

var chunk_coord: Vector2i
var ground: TileMapLayer
var wall: TileMapLayer
var decor: TileMapLayer
## Spawn entries overlapping this chunk, with a `world_tile` field resolved (Task 9: consumed
## by WgEntitySpawner via WorldStreamer.chunk_loaded).
var spawn_data: Array = []


func setup(coord: Vector2i, origin_px: Vector2, floor_tileset: TileSet, object_tileset: TileSet,
		quadrant: int) -> void:
	chunk_coord = coord
	position = origin_px

	ground = TileMapLayer.new()
	ground.name = "ground"
	ground.tile_set = floor_tileset

	wall = TileMapLayer.new()
	wall.name = "wall"
	wall.tile_set = floor_tileset
	wall.physics_quadrant_size = quadrant

	decor = TileMapLayer.new()
	decor.name = "decor"
	decor.tile_set = object_tileset
	decor.physics_quadrant_size = quadrant

	add_child(ground)
	add_child(wall)
	add_child(decor)


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
