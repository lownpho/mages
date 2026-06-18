class_name BiomePainter extends RefCounted
## Fills one biome's cells however it likes — but only within `cells`, and only into this
## biome's layers. The default is ScatterPainter; a biome that needs bespoke layout points
## its BiomeResource.painter at a subclass.

func fill(_ctx: GenContext, _biome: BiomeResource, _cells: Array[Vector2i], _rng: RandomNumberGenerator) -> void:
	push_error("BiomePainter.fill() is abstract — override it")


# --- Shared placement helpers (deterministic; subclasses use these) ---

# Tile centre nudged by a sub-tile offset. Enemies spawned dead-centre share an exact y with
# every other enemy in the same row; overlapping y-sorted sprites that tie on y flip draw order
# frame-to-frame (flicker). The nudge keeps them inside their tile but breaks the tie, and
# de-grids the look. Mirrors the loot-drop scatter in world.gd.
func _scatter_pos(ctx: GenContext, cell: Vector2i, rng: RandomNumberGenerator) -> Vector2:
	var jitter := GameConstants.PX_PER_TILE * 0.5 - 1.0
	var off := Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
	return ctx.tile_to_world(cell) + off


func _pick(arr: Array, rng: RandomNumberGenerator):
	return arr[rng.randi() % arr.size()]


# Deterministic Fisher-Yates (Array.shuffle() uses the global RNG, which isn't reproducible).
func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for n in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, n)
		var tmp = arr[n]
		arr[n] = arr[j]
		arr[j] = tmp
