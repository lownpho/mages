class_name FixedEncounterResource
extends Resource
## A Rare, Miniboss or Boss: one leader plus escorts. Written as a sub-resource of the Biome or Zone
## that places it. It ignores the density curve and walkable area.

@export var leader: CreatureResource
## Escort -> how many. Dictionary order carries no meaning.
@export var escorts: Dictionary[CreatureResource, int] = {}
## Places the leader on the Room's centre.
@export var centred := false
