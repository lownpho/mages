extends SpellResource
class_name BlinkResource

## Max teleport distance from the caster, in tiles. The destination is the
## cursor, clamped to this radius — the doc's "within the current room".
@export var range_tiles: float = 8.0
