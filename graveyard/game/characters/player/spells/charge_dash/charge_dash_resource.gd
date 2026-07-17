extends SpellResource
class_name ChargeDashResource

@export_group("Charge Dash")
## Dash speed in px/s.
@export var dash_speed: float = 520.0
## Seconds the dash lasts.
@export var duration: float = 0.4
## Seconds between perpendicular volleys fired during the dash.
@export var fire_interval: float = 0.08
## The bullet fired out each side (90° to the dash).
@export var bullet: BulletResource
