class_name WorldGenerator extends MapGenerator
## Overworld generator: partition -> fill -> (fixtures, TODO). This is the Glade vertical
## slice — the partition is stubbed to "the whole map is the first biome." Step 2 replaces
## _partition() with a real Voronoi/zone split that tags each cell with a biome.

func generate(ctx: GenContext) -> void:
	if ctx.biomes.is_empty():
		push_error("WorldGenerator: GenContext.biomes is empty")
		return

	for region in _partition(ctx):
		var biome: BiomeResource = region.biome
		var cells: Array[Vector2i] = region.cells
		# Ring the region in the wall terrain (impassable edge) when the biome defines one;
		# the painter then fills only the interior. Floor/wall autotile their shared border.
		if biome.wall_terrain_id >= 0:
			cells = _wall_border(ctx, biome, cells)
		var painter: BiomePainter = biome.painter.new() if biome.painter else ScatterPainter.new()
		painter.fill(ctx, biome, cells, ctx.rng_for(region.id))


# Paint the outer ring of `cells` as wall terrain (collision comes from the wall tiles), and
# return the interior cells for the painter to floor + scatter.
func _wall_border(ctx: GenContext, biome: BiomeResource, cells: Array[Vector2i]) -> Array[Vector2i]:
	var b := ctx.bounds
	var wall: Array[Vector2i] = []
	var interior: Array[Vector2i] = []
	for cell in cells:
		if cell.x == b.position.x or cell.y == b.position.y or cell.x == b.end.x - 1 or cell.y == b.end.y - 1:
			wall.append(cell)
		else:
			interior.append(cell)
	ctx.ground.set_cells_terrain_connect(wall, biome.terrain_set, biome.wall_terrain_id, false)
	return interior


# Slice stub: one region covering the whole bounds, painted as biomes[0] (Glade).
func _partition(ctx: GenContext) -> Array:
	var cells: Array[Vector2i] = []
	for y in range(ctx.bounds.position.y, ctx.bounds.end.y):
		for x in range(ctx.bounds.position.x, ctx.bounds.end.x):
			cells.append(Vector2i(x, y))
	return [{"id": 0, "biome": ctx.biomes[0], "cells": cells}]
