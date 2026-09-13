class_name GeneratedRoom
extends RefCounted
## One Room of the room graph: its planned place, its power-diagram cell in unwarped World tiles,
## its role, its Passages and the Object sites fixed in it. WorldGraph owns the shared warp and
## answers which Room owns a tile.

enum Role { TESTING, TEACHING, BREATHER, SPAWN, BOSS, MINIBOSS, RARE }

const ROLE_NAMES: Array[StringName] = [&"testing", &"teaching", &"breather", &"spawn", &"boss", &"miniboss", &"rare"]

var plan: RoomPlan
## Its place in WorldGraph.room_list, which packed per-tile owner arrays store; -1 until the graph
## is joined.
var index := -1
## The power-diagram seed, in unwarped World tiles. An ordinary Room's Object spots default to it.
var seed := Vector2.ZERO
## A set piece's protected radius in tiles; 0 for an ordinary Room.
var radius := 0.0
## Its cell of the power diagram, clipped to its macro cell, in unwarped World tiles.
var polygon := PackedVector2Array()
var role := Role.TESTING
## The enemy a Teaching room introduces; null otherwise.
var teaching: CreatureResource
var passages: Array[RoomPassage] = []
var sites: Array[ObjectSite] = []
## Enemy -> effective Entry challenge where this Room stands: its Biome's roster plus its Zone's,
## with the Zone's lowest-entry enemies eligible from the Zone's first Room. Shared by the Zone.
var roster: Dictionary[CreatureResource, int] = {}
## The roster's Fillers.
var fillers: Array[CreatureResource] = []


func key() -> String:
	return plan.key


## Not a set piece. The spawn is a set piece on the route.
func is_ordinary() -> bool:
	return not plan.is_set_piece()


func is_set_piece() -> bool:
	return plan.is_set_piece()


## A set piece other than the spawn: off-route, with exactly one Passage.
func is_isolated() -> bool:
	return plan.is_set_piece() and plan.kind != RoomPlan.Kind.SPAWN


func role_name() -> StringName:
	return ROLE_NAMES[role]


func rockiness(content: WorldContent) -> float:
	return content.biomes[plan.biome].rockiness * (1.0 if is_ordinary() else 0.3)


func neighbour(passage: RoomPassage) -> String:
	return passage.other(key())
