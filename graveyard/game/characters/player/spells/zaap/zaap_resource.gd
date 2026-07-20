extends SpellResource
class_name ZaapResource

@export_group("Zaap")
## Hits after the first: the chain reaches up to 1 + bounces enemies.
@export var bounces: int = 3
@export var speed_tiles: float = 30.0
## Max initial flight before the bolt fizzles without zapping anyone.
@export var range_tiles: int = 12
## Max leap distance to the next enemy in the chain.
@export var bounce_range_tiles: float = 6.0
@export var projectile_texture: Texture2D
