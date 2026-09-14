class_name WorldObjects
extends RefCounted
## Every planned Object of a WorldGraph as the game receives it: its scene, the chunk it stands in
## and the data its setup(data) takes. Signs share one scene and Warp doors another, each door
## wearing its destination Biome's door art; a weighted Object brings the scene its Breather drew.
## Landings are clear spots, not Objects, and build nothing.
##
## Setup data always holds the Object's "key" (its site key, derived from its place), "kind" and
## "room_key". A Sign adds "text" and "reveal_key"; a Warp door adds "destination_room", "landing"
## (a tile) and "art" (a Door.Style). ObjectSpawner adds the Object's own "state".
##
## No Professor scene exists yet, so Professor sites build nothing.

const SIGN_SCENE := preload("res://objects/sign/under_construction_sign.tscn")
const DOOR_SCENE := preload("res://objects/door/door.tscn")

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


## The scene a site builds, or null for a landing or a Professor.
func scene_for(site: ObjectSite) -> PackedScene:
	match site.kind:
		ObjectSite.Kind.SIGN:
			return SIGN_SCENE
		ObjectSite.Kind.DOOR:
			return DOOR_SCENE
		ObjectSite.Kind.WEIGHTED:
			return site.scene
	return null


func setup_data(site: ObjectSite) -> Dictionary:
	var data := {"key": site.key, "kind": site.kind_name(), "room_key": site.room_key}
	match site.kind:
		ObjectSite.Kind.SIGN:
			data.text = site.sign_resource.text
			data.reveal_key = site.reveal_key
		ObjectSite.Kind.DOOR:
			var presentation := graph.plan.content.biomes[site.destination_biome].presentation
			data.destination_room = site.destination_room
			data.landing = graph.sites[site.landing_key].spot
			data.art = presentation.door_style if presentation != null else Door.Style.WOOD
	return data
