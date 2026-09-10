extends BulletSpellResource
class_name ChargeDashResource

## An ordinary bullet spell that happens to move its caster: the burst IS the shed bullets,
## and these two dials are the run they're shed along. Author the burst to last about as
## long as the dash, or the trail stops short of where the caster ends up.

@export_group("Charge Dash")
## Dash speed in px/s.
@export var dash_speed: float = 520.0
## Seconds the dash lasts.
@export var dash_duration: float = 0.4
## What the run itself deals to whatever it goes through, once per target. The shed bullets
## peel off the flanks, so without this a target standing dead on the line takes nothing.
## null = the run is harmless and only the bullets hit.
@export var contact_damage: ScalingProfile
## Radius of that contact hit, in tiles.
@export var contact_radius_tiles: float = 1.0
