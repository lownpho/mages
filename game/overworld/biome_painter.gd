class_name BiomePainter extends RefCounted
## Fills one biome's cells however it likes — but only within `cells`, and only into this
## biome's layers. The default is ScatterPainter; a biome that needs bespoke layout points
## its BiomeResource.painter at a subclass.

func fill(_ctx: GenContext, _biome: BiomeResource, _cells: Array[Vector2i], _rng: RandomNumberGenerator) -> void:
	push_error("BiomePainter.fill() is abstract — override it")
