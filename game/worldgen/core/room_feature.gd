class_name RoomFeature
## One feature placement on a room type: a specific scene (door, sign, altar, portal) plus an
## optional data Resource applied via the instance's `setup(data)` method, a placement hint, and
## a count range. A RoomTypeDef carries an ARRAY of these. Like presentation, features are an
## overlay on the finished room — deliberately NOT hashed, so swapping them never re-rolls a
## saved world. Placement draws come from the NS_FEATURES stream (see Population), never from
## the population RNG, so features can never shift enemy identity.
extends Resource

## CENTER: the deterministic room-centre tile (nearest reachable), no RNG draw.
## RANDOM_REACHABLE: a random reachable tile. NEAR_WALL: a random reachable tile 4-adjacent to
## a WALL/BLOCKER (falls back to RANDOM_REACHABLE, then CENTER, when the pool is empty).
enum Placement { CENTER, RANDOM_REACHABLE, NEAR_WALL }

@export var scene: PackedScene = null       ## instantiated by WgEntitySpawner; null = entry skipped
@export var data: Resource = null           ## optional; applied via the scene's setup(data)
@export var placement: Placement = Placement.CENTER
@export var count_min: int = 1
@export var count_max: int = 1
