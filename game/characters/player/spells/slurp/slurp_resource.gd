extends SpellResource
class_name SlurpResource

@export_group("Slurp")
## Fraction of the damage dealt each tick that the caster drinks back as health.
@export var heal_fraction: float = 0.5
## Drain radius around the player, in tiles.
@export var range_tiles: float = 5.0
## Seconds between damage/heal ticks while the beam is held.
@export var tick_interval: float = 0.2
