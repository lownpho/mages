class_name ZoneResource
extends Resource
## A Zone, authored in biomes/<biome>/zones/<id>.tres. It adds content to its Biome's and carries
## its Room quotas wherever the seeded Zone order places it.

## The Spawn zone: exactly one, in the Ideal path's first Biome, and always its first Zone.
@export var spawn := false
## Rooms on the Ideal path, or on the Side route. The spawn consumes one.
@export_range(1, 200, 1, "or_greater") var route_rooms := 0
## Every Room the Zone owns: its route Rooms, set pieces, Teaching and Testing rooms and Breathers.
@export_range(1, 500, 1, "or_greater") var room_count := 0
## Enemy -> Entry challenge, added to the Biome's roster. May not repeat a Biome roster enemy.
@export var roster: Dictionary[CreatureResource, int] = {}
## Enemies of this Zone's own roster that join every ordinary encounter once eligible.
@export var fillers: Array[CreatureResource] = []
@export var minibosses: Array[FixedEncounterResource] = []
@export var rares: Array[FixedEncounterResource] = []

@export_group("Presentation")
## Overrides the Biome's decoration tileset. null keeps the Biome's.
@export var decoration_tileset: TileSet
## Overrides the Biome's decoration density. -1 keeps the Biome's.
@export_range(-1.0, 1.0, 0.005) var decoration_density := -1.0

@export_group("Objects")
@export var signs: Array[SignResource] = []
## Scene -> weight for Breather Objects, added to the Biome's.
@export var breather_objects: Dictionary[PackedScene, int] = {}
