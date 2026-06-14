extends SpellResource
class_name SploomResource

@export_group("Sploom")
@export var speed_tiles: float = 4.0
@export var range_tiles: int = 10
## How hard the bomb curves toward the nearest enemy (velocity lerp weight/sec).
@export var homing_weight: float = 4.0
## Radius of the central detonation blast, in tiles.
@export var aoe_tiles: float = 2.0
## Bullets sprayed outward in an even ring on detonation.
@export var ring_bullets: int = 6
## Stats for the ring bullets — embedded sub-resource, like a weapon's bullet.
@export var ring_bullet: BulletResource
@export var projectile_texture: Texture2D
