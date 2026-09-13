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


## Every room graph of a planned World, building its macro cells in order first when given.
func graph(world_seed: int, radii: Dictionary[StringName, int] = WorldPlan.DEFAULT_RADII, order: Array[Vector2i] = []) -> WorldGraph:
	return WorldGraph.build(plan(world_seed, radii), order)


## The six spatial knobs every Biome authors.
const KNOBS: Array[StringName] = [&"room_size", &"border_warp", &"loops", &"shortcuts", &"passage_width", &"rockiness"]


## A knob's slider range, from BiomeResource's export hint: [minimum, maximum].
static func knob_range(knob: StringName) -> Array:
	for property in BiomeResource.new().get_property_list():
		if property.name == knob:
			var bounds: PackedStringArray = property.hint_string.split(",")
			if property.type == TYPE_INT:
				return [bounds[0].to_int(), bounds[1].to_int()]
			return [bounds[0].to_float(), bounds[1].to_float()]
	return []


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


## A graph's public outputs as text, one line per Room, Passage and site: graphs with equal
## snapshots are the same World.
static func graph_snapshot(graph: WorldGraph) -> String:
	var lines: Array[String] = [snapshot(graph.plan)]
	for key in graph.rooms:
		var room := graph.rooms[key]
		lines.append("graph room %s %s teaches %s seed %s radius %s polygon %s roster %s passages %s sites %s" % [key, room.role_name(),
				room.teaching.resource_path if room.teaching else "-", room.seed, room.radius, room.polygon,
				room.roster.keys().map(func(enemy: CreatureResource) -> String: return "%s:%d" % [enemy.resource_path.get_file(), room.roster[enemy]]),
				room.passages.map(func(passage: RoomPassage) -> String: return passage.key),
				room.sites.map(func(site: ObjectSite) -> String: return site.key)])
	for key in graph.passages:
		var passage := graph.passages[key]
		lines.append("passage %s %s spot %s point %s width %d" % [key, passage.kind_name(), passage.spot, passage.point, passage.width])
	for key in graph.sites:
		var site := graph.sites[key]
		lines.append("site %s %s spot %s scene %s sign %s reveals %s door %s %s %s %s" % [key, site.kind_name(), site.spot,
				site.scene.resource_path if site.scene else "-", site.sign_resource.text.get_slice("\n", 0) if site.sign_resource else "-",
				site.reveal_key, site.destination_biome, site.destination_room, site.landing_key, site.door_key])
	return "\n".join(lines)
