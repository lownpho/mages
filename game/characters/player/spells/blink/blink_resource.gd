extends SpellResource
class_name BlinkResource

## Blink: the caster vanishes and reappears elsewhere. Two dials cover every use in the
## game — where the hop aims, and how far it carries.

@export_group("Blink")
## How far the hop carries, in tiles.
@export var distance_tiles: float = 4.0
## Where it lands. AIM is the player's mobility hop (aim is a direction, never the cursor,
## so the distance is fixed rather than clamped to a click); RANDOM is a harasser resetting
## the engagement (shade, elder stalker); BEHIND puts the caster past its target, at your
## back (umbra).
@export_enum("Aim", "Random", "Behind") var landing: int = LANDING_AIM

const LANDING_AIM := 0
const LANDING_RANDOM := 1
const LANDING_BEHIND := 2
