extends SpellResource
class_name KaboomResource

@export_group("Kaboom")
@export var meteor_count: int = 4
## Impact points scatter within this radius (tiles) around the cursor.
@export var scatter_radius_tiles: float = 6.0
## Explosion diameter in tiles — the explosion sprites are drawn at exactly
## aoe_tiles × PX_PER_TILE pixels so the visual matches the hitbox.
@export var aoe_tiles: float = 3.0
## Seconds between the ground marks appearing and the meteors landing.
@export var impact_delay: float = 2
## Extra random delay per meteor, so the volley rains instead of landing at once.
@export var impact_jitter: float = 0.3
## Ground mark telegraphing each impact point — sized to match aoe_tiles.
@export var mark_texture: Texture2D
@export var explosion_frames: SpriteFrames
