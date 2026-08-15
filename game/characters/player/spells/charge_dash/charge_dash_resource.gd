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
