extends SpellResource
class_name PiercingLightsResource

@export_group("Piercing Lights")
@export var projectile_count: int = 10
@export var speed_tiles: float = 20.0
## Lights spawn scattered within this radius around the caster.
@export var spawn_radius_tiles: float = 2.0
## Every light hangs in place this long before it can launch.
@export var hang_time: float = 0.3
## Extra hang per light, so the volley fires off one by one — the staccato.
@export var launch_stagger: float = 0.06
@export var projectile_texture: Texture2D
