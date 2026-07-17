extends SpellResource
class_name BrrrResource

@export_group("Brrr")
## Ticks over a full channel (tick interval = cast_time / ticks). Each tick
## grows the burst radius by 1 tile (starting at 1) and adds one base_damage.
@export var ticks: int = 2
