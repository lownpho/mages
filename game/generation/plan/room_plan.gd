class_name RoomPlan
extends RefCounted
## One Room of the World plan: allocated to its Biome, Zone and macro cell, with its route position
## and Challenge, before any geometry exists. Room graphs give it a shape and Passages.

enum Kind { ORDINARY, SPAWN, BOSS, MINIBOSS, RARE }

## Kind -> its name, which also keys WorldPlan.radii.
const KIND_NAMES: Array[StringName] = [&"ordinary", &"spawn", &"boss", &"miniboss", &"rare"]

## Place-derived and unique in the World. An ordinary Room is "<cell key>/<index in its cell>"; a set
## piece takes its World-plan entry: "spawn", "boss/<biome>", "miniboss/<biome>/<zone>/<n>" or
## "rare/<biome>/<zone>/<n>", n indexing the Zone's authored list.
var key := ""
## Ordinary Rooms take their Teaching, Testing or Breather roles later. The spawn is a route Room;
## every other set piece is off-route.
var kind := Kind.ORDINARY
var biome := &""
var zone := &""
var cell := Vector2i.ZERO
## Its position on its Biome's route (its Ideal-path stretch or Side route), or -1 off-route.
var route_index := -1
## The route position it joins the route at: its own for a route Room.
var join_index := -1
## Rises along the route; an off-route Room takes its join's.
var challenge := 0
## The Boss, Miniboss or Rare a set piece holds; null otherwise.
var encounter: FixedEncounterResource


func is_on_route() -> bool:
	return route_index >= 0


func is_set_piece() -> bool:
	return kind != Kind.ORDINARY


func kind_name() -> StringName:
	return KIND_NAMES[kind]
