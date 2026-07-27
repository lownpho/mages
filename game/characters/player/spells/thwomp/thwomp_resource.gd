extends SpellResource
class_name ThwompResource

@export_group("Thwomp")
## Radius of the pulse in tiles.
@export var radius_tiles: float = 3.0
## Knockback impulse (px/s) applied at the centre, falling to zero at the edge.
@export var knockback_force: float = 800.0
## The pulse's hit — named `damage` so CastContext samples it like any other cast's.
@export var damage: ScalingProfile
## Fraction of the full hit landed at the very edge of the radius; the centre always takes
## the whole number. The design's "more damage the closer, chip at the edge".
@export_range(0.0, 1.0) var edge_damage: float = 0.35
