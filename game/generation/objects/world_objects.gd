class_name WorldObjects
extends RefCounted
## Every planned Object of a WorldGraph as the game receives it: its scene, the chunk it stands in
## and the data its setup(data) takes. Signs share one scene and Professors another; a weighted
## Object brings the scene its Breather drew. Landings are clear spots, not Objects, and build
## nothing.
##
## Setup data always holds the Object's "key" (its site key, derived from its place), "kind" and
## "room_key". A Sign adds "text" and "reveal_key". A Professor adds "biome" and "page" (the enemy
## ids on the Bestiary page it reads), "next_biome" (&"" when nothing lies onward), "opens_portal"
## and, by that kind, either "reward_item" or a portal's "destination_room", "landing" (a tile) and
## "art" (a Door.Style). ObjectSpawner adds the Object's own "state".

const SIGN_SCENE := preload("res://objects/sign/sign.tscn")
const PROFESSOR_SCENE := preload("res://objects/professor/professor.tscn")

var graph: WorldGraph
## Chunk size -> chunk coord -> the Objects standing in it, in key order.
var _bins: Dictionary[int, Dictionary] = {}


func _init(world_graph: WorldGraph) -> void:
	graph = world_graph


## The planned Objects standing in one chunk, in key order.
func in_chunk(coord: Vector2i, chunk_tiles: int) -> Array[ObjectSite]:
	if not _bins.has(chunk_tiles):
		var bins: Dictionary[Vector2i, Array] = {}
		var keys: Array[String] = []
		keys.assign(graph.sites.keys())
		keys.sort()
		for key in keys:
			var site := graph.sites[key]
			if site.is_object():
				var chunk := Vector2i(floori(float(site.spot.x) / chunk_tiles), floori(float(site.spot.y) / chunk_tiles))
				bins.get_or_add(chunk, []).append(site)
		_bins[chunk_tiles] = bins
	var out: Array[ObjectSite] = []
	out.assign(_bins[chunk_tiles].get(coord, []))
	return out


## The scene a site builds, or null for a landing.
func scene_for(site: ObjectSite) -> PackedScene:
	match site.kind:
		ObjectSite.Kind.SIGN:
			return SIGN_SCENE
		ObjectSite.Kind.PROFESSOR:
			return PROFESSOR_SCENE
		ObjectSite.Kind.WEIGHTED:
			return site.scene
	return null


func setup_data(site: ObjectSite) -> Dictionary:
	var data := {"key": site.key, "kind": site.kind_name(), "room_key": site.room_key}
	match site.kind:
		ObjectSite.Kind.SIGN:
			data.text = site.sign_resource.text
			data.reveal_key = site.reveal_key
		ObjectSite.Kind.PROFESSOR:
			var biome_id: StringName = graph.rooms[site.room_key].plan.biome
			data.biome = biome_id
			data.page = page_ids(biome_id)
			data.next_biome = site.destination_biome
			data.opens_portal = site.opens_portal
			data.reward_item = site.reward_item
			data.destination_room = site.destination_room
			data.landing = graph.sites[site.landing_key].spot if graph.sites.has(site.landing_key) else Vector2i.MAX
			data.art = _portal_art(site.destination_biome)
	return data


## The art a Professor's portal into a Biome wears. Door.Style has a PORTAL frame reserved, but none
## is drawn yet, so a portal wears that Biome's door instead.
func _portal_art(biome_id: StringName) -> Door.Style:
	var biome: BiomeResource = graph.plan.content.biomes.get(biome_id)
	var presentation := biome.presentation if biome != null else null
	return presentation.door_style if presentation != null else Door.Style.WOOD


## The enemy ids on a Biome's Bestiary page, sorted — what a Professor standing in that Biome counts
## its visitor's kills against.
func page_ids(biome_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for creature in graph.plan.content.biome_enemies(biome_id):
		var id := creature.enemy_id()
		if id != &"" and not out.has(id):
			out.append(id)
	out.sort()
	return out
