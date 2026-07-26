extends SpellResource
class_name BwoomResource

@export_group("Bwoom")
## Charge ticks at a full channel (tick interval = cast_time / max_ticks).
## Each tick grows the ball one art frame and multiplies the hit by one more `damage`.
@export var max_ticks: int = 3
## Flight speed after release.
@export var speed_tiles: float = 16.0
## The hit per charge tick — named `damage` so CastContext samples it like any other cast's.
@export var damage: ScalingProfile
## Range in tiles before the ball gives up, so a charged shot can't outlive the room.
@export var range_tiles: float = 24.0
