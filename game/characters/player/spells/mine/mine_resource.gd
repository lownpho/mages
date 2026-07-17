extends SpellResource
class_name MineResource

## A cast drops one or more floating mines that arm after a delay, then detonate
## when a hostile enters the trigger radius. The payload is data-driven so one
## effect serves both Ploop (a burst of piercing darts) and Oop (an AoE blast):
## set explode_radius_tiles for a blast, and/or burst_pattern + burst_bullet for
## a spray. Damage scales with speed (mines are a speed-archetype tool).

@export_group("Mine")
## Mines dropped per cast (higher tiers drop more).
@export var mine_count: int = 1
## Seconds before a mine becomes live.
@export var arm_delay: float = 0.6
## A hostile within this many tiles of an armed mine detonates it.
@export var trigger_radius_tiles: float = 2.5
## Placement scatter around the caster (tiles) when dropping several.
@export var scatter_tiles: float = 1.5
## Seconds a mine sits before expiring harmlessly if never triggered.
@export var mine_lifetime: float = 12.0
## Sprite for each mine (falls back to the spell icon).
@export var mine_texture: Texture2D

@export_group("Payload")
## AoE blast radius on detonation (Oop). 0 = no blast.
@export var explode_radius_tiles: float = 0.0
## Dart spray on detonation (Ploop): a FirePattern + the bullet it sprays.
@export var burst_pattern: FirePattern
@export var burst_bullet: BulletResource
