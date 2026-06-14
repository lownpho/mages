extends SpellResource
class_name ZoingResource

@export_group("Zoing")
@export var speed_tiles: float = 18.0
## Max travel per flight leg — each wall bounce starts a fresh leg.
@export var range_per_leg_tiles: int = 8
## Wall bounces before the bolt dies.
@export var bounces: int = 2
@export var projectile_texture: Texture2D
