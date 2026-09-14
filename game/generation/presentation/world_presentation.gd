class_name WorldPresentation
extends RefCounted
## How the World's semantic tiles look. A Room's Biome owns its floor, wall and rock art and minimap
## colours (BiomePresentation) and its default decoration; the Room's Zone may override the
## decoration tileset and density, each on its own. A tile takes the art of the Room owning it, so a
## Zone's decoration starts and stops exactly at its Rooms' walls, without blending. Tiles no Room
## owns take the art of the nearest macro cell a Biome owns, and show as wall.
##
## Decoration is a hash of the World seed, the tile and the owning Zone's key, placed only on floor.
## Nothing in generation reads it, so it never blocks, never moves an encounter or rock, and draws
## from no generation RNG.


## One Room's art, shared by every Room of its Zone.
class Art:
	var biome := &""
	## "<biome>/<zone>"; "" for tiles no Room owns.
	var zone_key := &""
	var presentation: BiomePresentation
	var decoration_tileset: TileSet
	## True when the Zone's decoration tileset replaces its Biome's, on a layer of its own.
	var zone_decoration := false
	## Decoration shows where a tile's hash falls below this u32 threshold.
	var decoration_threshold := 0
	var decoration_seed := 0
	## A Biome without rock art draws rocks as walls.
	var rocks_as_walls := false


var interiors: WorldInteriors
var world_seed := 0
var _room_art: Array[Art] = []
var _void_art: Dictionary[Vector2i, Art] = {}


func _init(world_interiors: WorldInteriors) -> void:
	interiors = world_interiors
	var plan := interiors.graph.plan
	world_seed = plan.world_seed
	var by_zone: Dictionary[String, Art] = {}
	for room in interiors.graph.room_list:
		var key := "%s/%s" % [room.plan.biome, room.plan.zone]
		if not by_zone.has(key):
			by_zone[key] = _zone_art(plan.biomes[room.plan.biome], plan.biomes[room.plan.biome].zone(room.plan.zone))
		_room_art.append(by_zone[key])


## The art of the Room with this index, or for -1, of the macro cell nearest the tile.
func art(owner_index: int, tile: Vector2i) -> Art:
	if owner_index >= 0:
		return _room_art[owner_index]
	var coord := Vector2i(floori(float(tile.x) / WorldPlan.CELL), floori(float(tile.y) / WorldPlan.CELL))
	if not _void_art.has(coord):
		_void_art[coord] = _nearest_art(coord)
	return _void_art[coord]


## Whether decoration shows on a floor tile of a Room with this art, from TilePicks.tile_hash():
## the tile hash is already mixed, so the Zone's seed only needs folding in.
static func decorates(room_art: Art, hashed_tile: int) -> bool:
	if room_art.decoration_threshold <= 0 or room_art.decoration_tileset == null:
		return false
	return ((hashed_tile ^ room_art.decoration_seed) & 0xFFFFFFFF) < room_art.decoration_threshold


## The chunk of chunk_tiles tiles square at a chunk coordinate, ready to step.
func chunk(coord: Vector2i, chunk_tiles: int) -> ChunkTiles:
	return ChunkTiles.new(self, coord, chunk_tiles)


func _zone_art(biome: BiomePlan, zone: ZonePlan) -> Art:
	var out := Art.new()
	out.biome = biome.id
	out.zone_key = StringName("%s/%s" % [biome.id, zone.id])
	out.presentation = biome.resource.presentation
	out.rocks_as_walls = out.presentation.rock_tileset == null
	out.zone_decoration = zone.resource.decoration_tileset != null
	out.decoration_tileset = zone.resource.decoration_tileset if out.zone_decoration else out.presentation.decoration_tileset
	var density := zone.resource.decoration_density if zone.resource.decoration_density >= 0.0 else biome.resource.decoration_density
	out.decoration_threshold = WorldHash.threshold(density)
	out.decoration_seed = WorldHash.unit_seed(world_seed, WorldHash.NS_DECORATION, out.zone_key)
	_warm(out)
	return out


## Void art: the Biome of the nearest owned macro cell, in rings, earliest in row order on ties.
func _nearest_art(coord: Vector2i) -> Art:
	var plan := interiors.graph.plan
	for ring in maxi(plan.size.x, plan.size.y) + 8:
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var cell: MacroCellPlan = plan.cells.get(coord + Vector2i(dx, dy))
				if cell != null:
					var out := Art.new()
					out.biome = cell.biome
					out.presentation = plan.biomes[cell.biome].resource.presentation
					out.rocks_as_walls = true
					_warm(out)
					return out
	return null


## Builds the art's pick tables now, so the first chunk showing it doesn't.
static func _warm(room_art: Art) -> void:
	var presentation := room_art.presentation
	for tileset: TileSet in [presentation.floor_tileset, presentation.wall_tileset, presentation.rock_tileset, room_art.decoration_tileset]:
		TilePicks.table(tileset)
	if presentation.floor_autotile:
		TilePicks.terrain_table(presentation.floor_tileset)
	if presentation.wall_autotile:
		TilePicks.terrain_table(presentation.wall_tileset)
