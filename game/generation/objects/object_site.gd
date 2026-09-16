class_name ObjectSite
extends RefCounted
## A fixed spot the room graph plans for an Object or a Warp-door landing, consumed by interiors,
## Object setup and the Map. Signs, Professors and Warp doors force their Rooms to be Breathers; a
## WEIGHTED Object is a chance Breather's draw. Landings are clear spots, not Objects, and leave their
## Rooms' roles alone.

enum Kind { SIGN, PROFESSOR, DOOR, LANDING, WEIGHTED }

const KIND_NAMES: Array[StringName] = [&"sign", &"professor", &"door", &"landing", &"weighted"]

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
## A Warp door's destination Biome, Room and the landing site there.
var destination_biome := &""
var destination_room := ""
var landing_key := ""
## A landing's door.
var door_key := ""


func is_object() -> bool:
	return kind != Kind.LANDING


func kind_name() -> StringName:
	return KIND_NAMES[kind]
