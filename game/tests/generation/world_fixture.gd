class_name WorldFixture
extends RefCounted
## The shared headless World driver for generation tests. It loads a test World's content once per
## process and builds generated output from seeds through the generator's public entry points, so
## tests assert what the game receives rather than the steps inside. Later layers (room graphs,
## interiors, encounters) are built from here too.
##
## Guarantees hold on the shipped World at SHIPPED_SEEDS and on the small fixture World.

const SHIPPED := "res://generation/world/"
const SMALL := "res://tests/generation/fixtures/small/"
const SHIPPED_SEEDS: Array[int] = [7, 90210, 1357924680]
const SMALL_SEEDS: Array[int] = [1, 2, 3]

static var _loaded: Dictionary[String, WorldContent] = {}

var content: WorldContent
var seeds: Array[int] = []
## Biome id -> {knob -> authored value}, for the knobs set_knob changed.
var _authored: Dictionary[StringName, Dictionary] = {}


static func shipped() -> WorldFixture:
	return WorldFixture.new(SHIPPED, SHIPPED_SEEDS)


static func small() -> WorldFixture:
	return WorldFixture.new(SMALL, SMALL_SEEDS)


func _init(root: String, world_seeds: Array[int]) -> void:
	if not _loaded.has(root):
		_loaded[root] = ContentLoader.load_content(root)
	content = _loaded[root]
	seeds = world_seeds


func plan(world_seed: int, radii: Dictionary[StringName, int] = WorldPlan.DEFAULT_RADII) -> WorldPlan:
	return WorldPlanner.plan(content, world_seed, radii)


## Sets a spatial knob on every Biome, as the debug tool's sliders do, until restore_knobs.
func set_knob(knob: StringName, value: Variant) -> void:
	for id in content.biomes:
		var authored: Dictionary = _authored.get_or_add(id, {})
		if not authored.has(knob):
			authored[knob] = content.biomes[id].get(knob)
		content.biomes[id].set(knob, value)


func restore_knobs() -> void:
	for id in _authored:
		for knob: StringName in _authored[id]:
			content.biomes[id].set(knob, _authored[id][knob])
	_authored.clear()


## Every set-piece radius at one value.
static func radii_at(radius: int) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for kind in WorldPlan.DEFAULT_RADII:
		out[kind] = radius
	return out


## A plan's public outputs as text, one line per cell, Biome and Room: plans with equal snapshots
## are the same World.
static func snapshot(plan: WorldPlan) -> String:
	var lines: Array[String] = ["size %s path %s radii %s" % [plan.size, plan.path, plan.radii]]
	for coord in plan.cells:
		var cell := plan.cells[coord]
		lines.append("cell %s %s #%d path %d in %s out %s rooms %s" % [cell.key, cell.biome, cell.stretch_index, cell.path_index,
				cell.entry, cell.exit, cell.rooms.map(func(room: RoomPlan) -> String: return room.key)])
	for id in plan.biomes:
		var biome := plan.biomes[id]
		lines.append("biome %s zones %s cells %s entry %d attachment %s" % [id,
				biome.zones.map(func(zone: ZonePlan) -> String: return "%s@%d" % [zone.id, zone.route_start]),
				biome.cells, biome.entry_challenge, biome.attachment.key if biome.attachment else "-"])
	for key in plan.rooms:
		var room := plan.rooms[key]
		lines.append("room %s %s %s/%s cell %s route %d join %d challenge %d %s" % [key, room.kind_name(), room.biome, room.zone,
				room.cell, room.route_index, room.join_index, room.challenge, room.encounter.resource_path if room.encounter else "-"])
	return "\n".join(lines)
