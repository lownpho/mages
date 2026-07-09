class_name RoomSpec
## One room's graph-level description: where it sits, how big it is, its type,
## and the passages on its four sides. A room is a BSP leaf — any w×h rectangle of slots up to
## the whole biome region. Produced by Layer 2 (RoomGraph); consumed by Layer 3. Pure data,
## RefCounted — no tiles here.
extends RefCounted

## Passage kind. Fixed order — a change bumps GEN_VERSION.
enum { KIND_DOOR = 0, KIND_OPEN = 1 }


## A traversable connection on one side of this room.
##
## `offset_tiles` convention (normative — the two rooms sharing an edge MUST agree geometrically):
##   The offset is measured in TILES from this room's own wall-segment START, where "start" is the
##   LOW-coordinate end of that side — the WEST end for a NORTH/SOUTH (horizontal) wall, the NORTH
##   end for an EAST/WEST (vertical) wall. A room's full wall segment on one side runs its entire
##   extent along that edge (up to 2 * room_slot_tiles for a merged 2-wide room).
##   - KIND_DOOR: the opening occupies tiles [offset_tiles, offset_tiles + width_tiles) along the
##     edge, in this room's own tile frame. width_tiles == door_width_tiles.
##   - KIND_OPEN: the whole shared segment is absent; [offset_tiles, offset_tiles + width_tiles)
##     spans exactly the segment shared with the neighbour (which may be a strict sub-range of this
##     room's full wall when the neighbour is smaller). width_tiles == shared segment length.
##   Because both rooms record the SAME absolute door/segment position — each just subtracting its
##   own edge-start — a door written from side A lands on identical world tiles as its twin on B.
## `external` marks a forced border-contract crossing to a neighbouring biome; those get
## no internal graph edge. `from_tree` is DEBUG-ONLY metadata (not part of the spec schema) letting
## the biome view colour tree edges vs loop edges.
class Passage extends RefCounted:
	var side: int          ## WorldSpec.SIDE_*
	var kind: int          ## KIND_DOOR | KIND_OPEN
	var offset_tiles: int
	var width_tiles: int
	var external: bool = false
	var from_tree: bool = false   ## DEBUG metadata only — not spec

	func _init(p_side := 0, p_kind := KIND_DOOR, p_offset := 0, p_width := 0,
			p_external := false, p_from_tree := false) -> void:
		side = p_side
		kind = p_kind
		offset_tiles = p_offset
		width_tiles = p_width
		external = p_external
		from_tree = p_from_tree


var origin_slot: Vector2i     ## top-left slot coord, WORLD slot space; also the cache key
var size_slots: Vector2i      ## (w, h) in slots — any BSP leaf rectangle
var type_id: StringName       ## room type
var biome_id: StringName      ## biome definition id
var passages: Array = []      ## of Passage
var depth: int = 0            ## BFS hops from the biome entrance over internal passages (L2)
var biome_max_depth: int = 0  ## max depth over this biome's rooms
## Bitmask (bit = WorldSpec.SIDE_*): the side borders sealed void — the world edge or an
## unclaimed macro-cell — along at least one of its slots. L3 never erodes a void side; its
## perimeter ring stays sealed.
var void_sides: int = 0


## Difficulty tier of this room's position: the biome's depth range split into quarters → 0..3.
## Room types are placed by matching their authored `difficulty` against this.
func tier() -> int:
	return tier_for(depth, biome_max_depth)


static func tier_for(p_depth: int, p_max_depth: int) -> int:
	@warning_ignore("integer_division")
	return mini(3, 4 * p_depth / maxi(1, p_max_depth))


func _init(p_origin := Vector2i.ZERO, p_size := Vector2i.ONE, p_biome_id := &"") -> void:
	origin_slot = p_origin
	size_slots = p_size
	biome_id = p_biome_id
	passages = []
