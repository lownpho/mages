extends SpellResource
class_name FireballResource

@export_group("Fireball")
@export var speed_tiles: float = 16.0
@export var range_tiles: int = 12
## Explosion diameter in tiles — the explosion sprites are drawn at exactly
## aoe_tiles × PX_PER_TILE pixels so the visual matches the hitbox.
@export var aoe_tiles: float = 3.0
@export var explosion_frames: SpriteFrames
