class_name RoomPassage
extends RefCounted
## One shared opening. Both Rooms reference this same value; walls are ownership changes, so there
## is no independently generated wall on the other side.
##
##   ROUTE       joins consecutive route Rooms, inside a macro cell or across its route edge
##   TREE, LOOP  join ordinary Rooms inside a macro cell: a spanning tree, then hashed loops
##   SHORTCUT    joins two ordinary Rooms across a macro-cell edge where Ideal-path stretches fold
##               alongside one another; at most one per edge
##   SET_PIECE   a Boss, Miniboss or Rare's only Passage
##   ATTACHMENT  a Side biome's only way in, from its parent's attachment Room

enum Kind { ROUTE, TREE, LOOP, SHORTCUT, SET_PIECE, ATTACHMENT }

const KIND_NAMES: Array[StringName] = [&"route", &"tree", &"loop", &"shortcut", &"set_piece", &"attachment"]

## The two Room keys, sorted and joined by "|". A pair of Rooms shares at most one Passage.
var key := ""
var a := ""
var b := ""
var kind := Kind.TREE
## The opening's centre on the shared border, in World tiles after the warp: owned by one of its
## Rooms, beside the other.
var spot := Vector2i.ZERO
## The unwarped border point the spot maps to.
var point := Vector2.ZERO
var width := 2


static func pair(room_a: String, room_b: String) -> String:
	return room_a + "|" + room_b if room_a < room_b else room_b + "|" + room_a


func other(room_key: String) -> String:
	assert(room_key == a or room_key == b)
	return b if room_key == a else a


func kind_name() -> StringName:
	return KIND_NAMES[kind]
