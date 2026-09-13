class_name MacroCellPlan
extends RefCounted
## One macro cell of the World plan, WorldPlan.CELL tiles square. It belongs to one Biome and holds a
## contiguous piece of its route with the off-route Rooms joining it. Grid cells no Biome owns lie
## outside the World's walkable space.

var coord := Vector2i.ZERO
## "<x>,<y>", which its ordinary Rooms' keys extend.
var key := ""
var biome := &""
## Its place in its Biome's cells.
var stretch_index := 0
## Its place on the folded Ideal path; -1 in a Side biome.
var path_index := -1
## Unit steps toward the cell the route arrives from and leaves to: Vector2i.ZERO where the route
## starts or ends. A Side biome's first cell arrives from its attachment's cell.
var entry := Vector2i.ZERO
var exit := Vector2i.ZERO
## Route Rooms in route order, then the off-route Rooms joining them.
var rooms: Array[RoomPlan] = []


## Its tiles.
func rect() -> Rect2i:
	return Rect2i(coord * WorldPlan.CELL, Vector2i.ONE * WorldPlan.CELL)
