extends SpellResource
class_name FireballResource

@export_group("Fireball")
@export var speed_tiles: float = 16.0
@export var range_tiles: int = 12
## Explosion diameter in tiles — the explosion sprites are drawn at exactly
## aoe_tiles × PX_PER_TILE pixels so the visual matches the hitbox.
@export var aoe_tiles: float = 3.0
@export var explosion_frames: SpriteFrames

@export_group("Aim assist")
## Steer onto the enemy nearest the cursor at cast (see AimAssist). The dials
## default to the Wand's strong tune.
@export var homing: bool = false
@export var homing_turn_deg: float = 720.0
@export var homing_cone_deg: float = 90.0
## Only lock an enemy within this many tiles of the cursor — aiming at empty
## space locks nothing, so the fireball flies straight.
@export var homing_aim_tiles: float = 6.0
