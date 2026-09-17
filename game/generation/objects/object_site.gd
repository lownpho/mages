class_name ObjectSite
extends RefCounted
## A fixed spot the room graph plans for an Object or a landing, consumed by interiors, Object setup
## and the Map. Signs and Professors force their Rooms to be Breathers; a WEIGHTED Object is a chance
## Breather's draw. Landings are clear spots, not Objects, and leave their Rooms' roles alone — a
## Professor whose gift is a portal onward owns one.

enum Kind { SIGN, PROFESSOR, LANDING, WEIGHTED }

const KIND_NAMES: Array[StringName] = [&"sign", &"professor", &"landing", &"weighted"]

## "<room key>/<kind>/<n>", n counting that kind in the Room.
var key := ""
var room_key := ""
var kind := Kind.WEIGHTED
## In World tiles after the warp, owned by its Room.
var spot := Vector2i.ZERO
## A WEIGHTED Object's scene.
var scene: PackedScene
var sign_resource: SignResource
## The Room a Sign reveals: the nearest planned Boss or Miniboss its enemy leads.
var reveal_key := ""
## A Professor's kind: a portal Professor opens a way into the Biome onward, an item Professor gives
## up one of the things that drop there. Seeded per site.
var opens_portal := false
## An item Professor's gift, drawn once from the Biome onward's drop pool. Null when that Biome
## drops nothing, or when this is a portal Professor or another kind of site.
var reward_item: ItemResource
## A portal Professor's destination Biome, Room and the landing site there, where its portal leads.
## destination_biome alone is also the Biome an item Professor's gift comes from, and is &"" when
## nothing lies onward.
var destination_biome := &""
var destination_room := ""
var landing_key := ""
## A landing's portal Professor.
var portal_key := ""


func is_object() -> bool:
	return kind != Kind.LANDING


func kind_name() -> StringName:
	return KIND_NAMES[kind]
