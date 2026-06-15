extends Resource
class_name BulletResource

@export var icon: Texture2D
@export var base_damage: float = 1
@export var range_tiles: int = 16
@export var speed_tiles: int = 128
@export var skill_scaling: float = 1.0
@export var homing: bool = false
@export var homing_weight: float = 5.0
## Target selection: only lock an enemy within this many tiles of the mouse
## cursor. Aiming at empty space locks nothing, so the shot flies straight.
@export var homing_aim_tiles: float = 6.0
## After travelling this far (tiles) the bullet stops steering and flies
## straight. 0 = home for a default fraction of range_tiles.
@export var homing_range_tiles: float = 0.0

@export_group("Ricochet")
## Wall bounces before the bullet dies. Each bounce reflects the velocity off the
## wall and restarts the range as a fresh leg, so total travel grows with bounces.
@export var wall_bounces: int = 0

@export_group("On Expire")
## When the bullet expires (wall, max range, or reaching a hurtbox) it spawns a
## one-shot AoE blast of this radius (tiles) dealing the bullet's own damage.
## 0 = no blast.
@export var explode_radius_tiles: float = 0.0
## Set together to fire a spray of sub-bullets on expire (e.g. a RingPattern for
## a bomb's outward burst). The sub-bullets inherit this bullet's collision layer,
## so an enemy-fired bomb bursts enemy bullets. Either null = no burst.
@export var burst_pattern: FirePattern
@export var burst_bullet: BulletResource
