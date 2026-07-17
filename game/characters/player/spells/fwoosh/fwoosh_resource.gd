extends SpellResource
class_name FwooshResource

@export_group("Fwoosh")
## Wall length from the caster toward the cursor, in tiles.
@export var wall_length_tiles: float = 5.0
## Wall thickness in tiles.
@export var wall_thickness_tiles: float = 1.2
## Seconds the wall persists.
@export var duration: float = 3.0
## Seconds between damage ticks — an enemy standing in the fire is re-hit each tick.
@export var tick_interval: float = 0.4
