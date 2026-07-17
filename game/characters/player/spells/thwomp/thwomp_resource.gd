extends SpellResource
class_name ThwompResource

@export_group("Thwomp")
## Radius of the pulse in tiles.
@export var radius_tiles: float = 3.0
## Knockback impulse (px/s) applied at the centre, falling to zero at the edge.
@export var knockback_force: float = 800.0
