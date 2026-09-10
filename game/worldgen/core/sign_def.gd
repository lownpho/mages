class_name SignDef
## One tip sign: the words on it and, optionally, what reading it marks on the map. A biome lists
## its signs on BiomeDef.signs and SignLinks scatters them over the biome's ordinary rooms — every
## listed sign stands at least once, most of them more. Sub-biomes of one family list the same
## .tres files. UnderConstructionSign.setup() applies it to the post itself.
##
## A sign naming `reveal_room_type` points somewhere: reading it drops a boss marker on the map at
## the nearest room of that type, found or not. Only bosses do this today, so the marker is always
## a boss marker (MapState.reveal_boss).
extends Resource

## Floated above the post while the player stands at it. The label doesn't wrap, so break lines by
## hand.
@export_multiline var message := ""

## Room type whose room reading this sign marks on the map (a boss room). &"" = marks nothing.
@export var reveal_room_type: StringName = &""

## Never authored: SignLinks resolves `reveal_room_type` to the nearest such room's origin slot and
## stamps it on a per-room copy, since only the links know the world's rooms. Vector2i.MAX = the
## sign marks nothing (no reveal asked for, or no room of that type in this world).
var reveal_slot := Vector2i.MAX
