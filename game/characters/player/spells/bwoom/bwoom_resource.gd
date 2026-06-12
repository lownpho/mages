extends SpellResource
class_name BwoomResource

@export_group("Bwoom")
## Charge ticks at a full channel (tick interval = cast_time / max_ticks).
## Each tick grows the ball one art frame and adds one base_damage.
@export var max_ticks: int = 3
## Flight speed after release.
@export var speed_tiles: float = 16.0
