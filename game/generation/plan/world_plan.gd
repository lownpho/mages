class_name WorldPlan
extends RefCounted
## The complete finite World as WorldPlanner.plan planned it, before any geometry: a grid of macro
## cells holding the folded Ideal path and each Side biome's branch, every Biome's seeded Zone order
## and route, every Room allocated to a Zone and a macro cell with its Challenge, the set pieces'
## World-plan entries and the Side-biome attachments. Room graphs, interiors and tiles build on it.
##
## Keys follow place: World -> macro cell ("3,2") -> Room ("3,2/5"); set pieces take their entry
## ("boss/glade"). The same content, radii and seed plan the same World within one version on one
## platform.

## A macro cell's side in tiles.
const CELL := 120
## Tiles each set piece protects around its seed, by RoomPlan kind name.
const DEFAULT_RADII: Dictionary[StringName, int] = {&"spawn": 12, &"boss": 22, &"miniboss": 16, &"rare": 10}
## The debug sliders' range for set-piece radii: up to a disc as wide as the widest Room, so a
## macro cell can still hold two set pieces beside its route.
const RADIUS_MIN := 4
const RADIUS_MAX := 32

const _ARROWS: Dictionary[Vector2i, String] = {Vector2i.RIGHT: ">", Vector2i.DOWN: "v", Vector2i.LEFT: "<", Vector2i.UP: "^"}

var world_seed := 0
var content: WorldContent
## Set-piece radii in tiles, by kind name: they size the macro cells a Biome needs.
var radii: Dictionary[StringName, int] = {}
## The grid in macro cells, cropped to the cells Biomes own.
var size := Vector2i.ZERO
## The folded Ideal path: every Ideal-path cell in route order, the spawn's first.
var path: Array[Vector2i] = []
## Every cell a Biome owns.
var cells: Dictionary[Vector2i, MacroCellPlan] = {}
## The Ideal path's Biomes in order, then the Side biomes.
var biomes: Dictionary[StringName, BiomePlan] = {}
## Every Room by key.
var rooms: Dictionary[String, RoomPlan] = {}
var spawn: RoomPlan


## The seed of a generated unit of this World.
func seed_for(namespace_id: int, key: String) -> int:
	return WgHash.unit_seed(world_seed, namespace_id, key)


func rng(namespace_id: int, key: String) -> RandomNumberGenerator:
	return WgHash.rng(seed_for(namespace_id, key))


## The route Room a Room joins the route at: itself for a route Room.
func join_of(room: RoomPlan) -> RoomPlan:
	return biomes[room.biome].route[room.join_index]


## The Ideal path's route Rooms in order, from the spawn to Fruit's exit.
func ideal_route() -> Array[RoomPlan]:
	var out: Array[RoomPlan] = []
	for id in content.ideal_path:
		out.append_array(biomes[id].route)
	return out


## The spawn and every Boss, Miniboss and Rare.
func set_pieces() -> Array[RoomPlan]:
	var out: Array[RoomPlan] = []
	for id in biomes:
		for room in biomes[id].rooms:
			if room.is_set_piece():
				out.append(room)
	return out


## The macro grid with its folded path, then each Biome's Zones, quotas, Challenge, set pieces and
## attachment.
func describe() -> String:
	var lines: Array[String] = []
	lines.append("World seed %d: %d x %d macro cells of %d tiles, %d owned, %d on the Ideal path; %d Rooms" % [
			world_seed, size.x, size.y, CELL, cells.size(), path.size(), rooms.size()])
	lines.append("Upper case: Ideal path. Lower case: Side biome. Arrows lead along the route; # ends it.")
	lines.append("")
	for y in size.y:
		var row := ""
		for x in size.x:
			row += _cell_label(Vector2i(x, y))
		lines.append(row.rstrip(" "))
	lines.append("")
	lines.append("%-11s %5s %5s %5s %9s  %s" % ["Biome", "Cells", "Route", "Rooms", "Challenge", "Zones in order: route/Rooms"])
	for id in biomes:
		var biome := biomes[id]
		var zones: Array[String] = []
		for zone in biome.zones:
			zones.append("%s %d/%d" % [zone.id, zone.resource.route_rooms, zone.rooms.size()])
		lines.append("%-11s %5d %5d %5d %4d-%-4d  %s" % [id, biome.cells.size(), biome.route.size(), biome.rooms.size(),
				biome.entry_challenge, biome.resource.exit_challenge, " > ".join(zones)])
	lines.append("")
	lines.append("Set pieces join route positions:")
	for id in biomes:
		var joins: Array[String] = []
		for room in biomes[id].rooms:
			if room.is_set_piece():
				joins.append("%s %d" % [room.kind_name(), room.join_index])
		lines.append("  %s: %s" % [id, ", ".join(joins)])
	lines.append("")
	lines.append("Side biomes attach at their parent's route Room:")
	for id in biomes:
		var biome := biomes[id]
		if biome.is_side():
			lines.append("  %s -> %s route %d of %d (%s, Challenge %d)" % [id, biome.parent, biome.attachment.route_index,
					biomes[biome.parent].route.size(), biome.attachment.key, biome.attachment.challenge])
	return "\n".join(lines)


func _cell_label(coord: Vector2i) -> String:
	var cell: MacroCellPlan = cells.get(coord)
	if cell == null:
		return " .  "
	var name := String(cell.biome).left(2)
	return (name.to_upper() if cell.path_index >= 0 else name) + _ARROWS.get(cell.exit, "#") + " "
