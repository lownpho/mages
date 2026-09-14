class_name MapState
extends RefCounted
## The Run's Map. The finite World records entered Room keys and renders one lazy image per macro
## cell; the old generator adapter below remains until ticket 12 removes the old generator.
##
## A macro cell's image paints each entered Room from its interior's classes, with the stubs of its
## Passages that lead into fog. A view never waits on an interior: a Room whose interior isn't built
## yet stays out of the image, joins wanted_interiors for streaming to build with spare frame budget,
## and appears on a later draw. Entering a Room redraws only the cells it and its Passage openings
## reach.

enum {
	MARKER_BOSS,
	MARKER_FEATURE, # legacy generated-world feature
	MARKER_FOUNTAIN,
	MARKER_DOOR,
	MARKER_SIGN,
	MARKER_NPC,
}

const ZOOM_TILES_PER_PX: Array[int] = [1, 2, 4, 8, 16, 32]

## Legacy room ids/scenes, kept only while the old generator exists.
const BOSS_TYPES: Array[StringName] = [
	&"glade_start_boss", &"glade_veggie_boss", &"deepwood_boss_gnarlking", &"mycelium_boss",
]
const _FOUNTAIN_SCENES: Array[PackedScene] = [
	preload("res://worldgen/runtime/fountain.tscn"),
	preload("res://worldgen/runtime/glade_fountain.tscn"),
	preload("res://worldgen/runtime/deepwood_fountain.tscn"),
	preload("res://worldgen/runtime/mycelium_fountain.tscn"),
]


class MacroImage:
	extends RefCounted
	var coord := Vector2i.ZERO
	var rect := Rect2i()
	var floor_image: Image
	var wall_image: Image
	var floor_texture: ImageTexture
	var wall_texture: ImageTexture
	var wall_levels: Dictionary = {}
	## Entered Rooms left out until their interior is built.
	var pending: Array[GeneratedRoom] = []


var world_seed := 0
var world_tiles := Vector2i.ZERO

## Finite-World save records. Values are sets so membership is constant-time and debug overlays can
## consume the dictionaries directly.
var entered_rooms: Dictionary[String, bool] = {}
var revealed_bosses: Dictionary[String, bool] = {}
var pins: Array = [] # Vector2i World tiles; fog is deliberately allowed.
var defeated_keys: Dictionary = {} # shared RunDefeats.defeated dictionary when running
## Entered Rooms a view drew without their interiors, in request order. GlobalMap hands them to
## streaming; take_wanted_interiors() empties it.
var wanted_interiors: Array[GeneratedRoom] = []

## Legacy save records retained until ticket 12 removes WorldStreamer.
var discovered: Dictionary = {}
var revealed: Array = []

## Legacy full-World textures. Finite views use images_in() instead.
var floor_texture: ImageTexture = null
var wall_texture: ImageTexture = null

var graph: WorldGraph = null
var interiors: WorldInteriors = null
var _streamer: WorldStreamer = null

var _legacy_markers: Array = []
var _boss_marked: Dictionary = {}
var _floor_img: Image = null
var _wall_img: Image = null
var _wall_levels: Dictionary = {}

var _macro_images: Dictionary[Vector2i, MacroImage] = {}
var _wanted: Dictionary[int, bool] = {}
var _scene_marker_kinds: Dictionary = {}
var _macro_builds := 0

## Derived every time so a Boss marker disappears as soon as its leader key enters RunDefeats.
var markers: Array:
	get:
		return _finite_markers() if graph != null else _legacy_markers


## Legacy setup used by the old generator's scenes.
func setup(streamer: WorldStreamer, zoom_levels: Array[int]) -> void:
	_streamer = streamer
	graph = null
	interiors = null
	world_seed = streamer.world_seed
	var s := streamer.config.biome_slots * streamer.config.room_slot_tiles
	world_tiles = Vector2i(streamer.world_spec.grid_w * s, streamer.world_spec.grid_h * s)
	_floor_img = Image.create_empty(world_tiles.x, world_tiles.y, false, Image.FORMAT_RGBA8)
	_wall_img = Image.create_empty(world_tiles.x, world_tiles.y, false, Image.FORMAT_RGBA8)
	floor_texture = ImageTexture.create_from_image(_floor_img)
	wall_texture = ImageTexture.create_from_image(_wall_img)
	_wall_levels.clear()
	for tpp in zoom_levels:
		if tpp > 1:
			var img := Image.create_empty(_ceil_div(world_tiles.x, tpp), _ceil_div(world_tiles.y, tpp),
					false, Image.FORMAT_RGBA8)
			_wall_levels[tpp] = {"img": img, "tex": ImageTexture.create_from_image(img)}
	_clear_records()


## Finite-World setup. Images and interiors remain untouched until a view asks for a macro cell.
## defeated is normally EncounterSpawner.defeats.defeated, retained by reference so marker removal
## needs no persisted marker list or special death notification.
func setup_finite(world_graph: WorldGraph, world_interiors: WorldInteriors,
		defeated: Dictionary = {}) -> void:
	graph = world_graph
	interiors = world_interiors
	_streamer = null
	world_seed = graph.plan.world_seed
	world_tiles = graph.plan.size * WorldPlan.CELL
	defeated_keys = defeated
	floor_texture = null
	wall_texture = null
	_floor_img = null
	_wall_img = null
	_wall_levels.clear()
	_macro_images.clear()
	_macro_builds = 0
	_scene_marker_kinds.clear()
	_clear_records()


func _clear_records() -> void:
	entered_rooms.clear()
	revealed_bosses.clear()
	discovered.clear()
	_legacy_markers.clear()
	pins.clear()
	revealed.clear()
	_boss_marked.clear()
	wanted_interiors.clear()
	_wanted.clear()


func is_finite_world() -> bool:
	return graph != null


func add_pin(world_tile: Vector2i) -> void:
	if world_tile not in pins:
		pins.append(world_tile)


func remove_pin_near(world_tile: Vector2i, radius_tiles: int) -> bool:
	var best := -1
	var best_d := radius_tiles * radius_tiles + 1
	for i in pins.size():
		var d: int = (pins[i] - world_tile).length_squared()
		if d <= radius_tiles * radius_tiles and d < best_d:
			best_d = d
			best = i
	if best >= 0:
		pins.remove_at(best)
		return true
	return false


## Finite Boss reveal by stable Room key. A discovered Boss and a revealed Boss derive the same
## marker, so repeated reveal/discovery never creates duplicates.
func reveal_boss_room(room_key: String) -> bool:
	if graph == null:
		return false
	var room: GeneratedRoom = graph.rooms.get(room_key)
	if room == null or room.role != GeneratedRoom.Role.BOSS or revealed_bosses.has(room_key):
		return false
	revealed_bosses[room_key] = true
	return true


## Legacy reveal by origin slot.
func reveal_boss(origin_slot: Vector2i) -> bool:
	if _streamer == null:
		return false
	var ss := _streamer.config.room_slot_tiles
	var spec := _streamer.room_spec_at_tile(origin_slot.x * ss, origin_slot.y * ss)
	if spec == null or spec.origin_slot != origin_slot:
		return false
	if origin_slot not in revealed:
		revealed.append(origin_slot)
	var size := spec.size_slots * ss
	return _mark_legacy_boss(origin_slot, origin_slot * ss + Vector2i(size.x >> 1, size.y >> 1))


func _mark_legacy_boss(origin_slot: Vector2i, world_tile: Vector2i) -> bool:
	if _boss_marked.has(origin_slot):
		return false
	_boss_marked[origin_slot] = true
	_legacy_markers.append({"tile": world_tile, "kind": MARKER_BOSS})
	return true


## Enter the Room owning world_tile. For the finite World this records only its key and forgets the
## images it changes; painting is deferred until images_in()/macro_image() is called by a view.
func discover_at(world_tile: Vector2i) -> bool:
	if graph != null:
		var room := graph.owner_at(world_tile)
		if room == null or entered_rooms.has(room.key()):
			return false
		entered_rooms[room.key()] = true
		var reach := _room_reach(room)
		for coord in _macro_images.keys():
			if _macro_images[coord].rect.intersects(reach):
				_macro_images.erase(coord)
		return true
	if _streamer == null:
		return false
	var spec := _streamer.room_spec_at_tile(world_tile.x, world_tile.y)
	if spec == null or discovered.has(spec.origin_slot):
		return false
	discovered[spec.origin_slot] = true
	var room := _streamer.get_room_output(spec)
	_paint_legacy_room(room)
	var ss := _streamer.config.room_slot_tiles
	_update_legacy_wall_levels(room.origin_slot.x * ss, room.origin_slot.y * ss, room.width, room.height)
	floor_texture.update(_floor_img)
	wall_texture.update(_wall_img)
	for tpp in _wall_levels:
		_wall_levels[tpp]["tex"].update(_wall_levels[tpp]["img"])
	return true


func discovered_bounds() -> Rect2i:
	if graph == null:
		return _floor_img.get_used_rect() if _floor_img != null else Rect2i()
	var out := Rect2i()
	var first := true
	for key in entered_rooms:
		var room: GeneratedRoom = graph.rooms.get(key)
		if room == null or room.polygon.is_empty():
			continue
		var bounds := _room_rect(room)
		out = bounds if first else out.merge(bounds)
		first = false
	return out


## Discovery is Room membership, not whether a pixel texture happens to have been built.
func is_tile_discovered(world_tile: Vector2i) -> bool:
	if graph != null:
		var room := graph.owner_at(world_tile)
		return room != null and entered_rooms.has(room.key())
	if _floor_img == null or world_tile.x < 0 or world_tile.y < 0 \
			or world_tile.x >= world_tiles.x or world_tile.y >= world_tiles.y:
		return false
	return _floor_img.get_pixelv(world_tile).a > 0.0


## Build and return each macro-cell image intersecting region. Each item has world_rect,
## floor_texture, wall_texture and texel_tiles, which lets both views blit finite and legacy Maps
## through one drawing path. Finite images never build interiors here: see wanted_interiors.
func images_in(region: Rect2, wall_tpp: int) -> Array:
	if graph == null:
		if floor_texture == null:
			return []
		return [{"world_rect": Rect2i(Vector2i.ZERO, world_tiles), "floor_texture": floor_texture,
				"wall_texture": wall_texture_for(wall_tpp), "texel_tiles": wall_tpp}]
	if not region.has_area():
		return []
	var first := Vector2i((region.position / WorldPlan.CELL).floor()).max(Vector2i.ZERO)
	var last := Vector2i(((region.end - Vector2(0.001, 0.001)) / WorldPlan.CELL).floor()) \
			.min(graph.plan.size - Vector2i.ONE)
	var out: Array = []
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var coord := Vector2i(x, y)
			if not graph.plan.cells.has(coord):
				continue
			var cell := macro_image(coord, false)
			out.append({"world_rect": cell.rect, "floor_texture": cell.floor_texture,
					"wall_texture": _macro_wall_texture(cell, wall_tpp), "texel_tiles": wall_tpp})
	return out


## Public visual-check seam: a cell is absent until requested and built once per change to what it
## shows. With build_interiors it builds every entered Room's interior it needs at once; without, a
## Room whose interior isn't cached is left out and added on a later request once it is.
func macro_image(coord: Vector2i, build_interiors := true) -> MacroImage:
	if graph == null or not graph.plan.cells.has(coord):
		return null
	var cell: MacroImage = _macro_images.get(coord)
	if cell != null:
		if not cell.pending.is_empty():
			_finish_pending(cell, build_interiors)
		return cell
	cell = MacroImage.new()
	cell.coord = coord
	cell.rect = Rect2i(coord * WorldPlan.CELL, Vector2i.ONE * WorldPlan.CELL)
	cell.floor_image = Image.create_empty(WorldPlan.CELL, WorldPlan.CELL, false, Image.FORMAT_RGBA8)
	cell.wall_image = Image.create_empty(WorldPlan.CELL, WorldPlan.CELL, false, Image.FORMAT_RGBA8)
	for room in _entered_rooms_reaching(cell.rect):
		var interior := interiors.interior(room) if build_interiors else interiors.cached(room)
		if interior != null:
			_paint_room(cell, interior)
		else:
			cell.pending.append(room)
			_want(room)
	cell.floor_texture = ImageTexture.create_from_image(cell.floor_image)
	cell.wall_texture = ImageTexture.create_from_image(cell.wall_image)
	_macro_images[coord] = cell
	_macro_builds += 1
	return cell


## Builds what a Continue shows first within budget_usec: entered Rooms' interiors, nearest the
## player's tile first. Rooms left over are built as the Map asks for them.
func prepare_discovered(near_tile: Vector2i, budget_usec: int) -> void:
	if graph == null:
		return
	var deadline := Time.get_ticks_usec() + budget_usec
	var keys := PackedInt64Array()
	for key in entered_rooms:
		var room: GeneratedRoom = graph.rooms[key]
		keys.append((int(room.seed.distance_squared_to(near_tile)) << 20) | room.index)
	keys.sort()
	for sort_key in keys:
		if Time.get_ticks_usec() >= deadline:
			break
		var build := interiors.building(graph.room_list[sort_key & 0xFFFFF])
		if build.step(deadline):
			interiors.finish(build)


## The entered Rooms views drew without interiors since the last call, for streaming to build.
func take_wanted_interiors() -> Array[GeneratedRoom]:
	var out := wanted_interiors
	wanted_interiors = []
	_wanted.clear()
	return out


func built_macro_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_macro_images.keys())
	return out


func macro_build_count() -> int:
	return _macro_builds


func _want(room: GeneratedRoom) -> void:
	if not _wanted.has(room.index):
		_wanted[room.index] = true
		wanted_interiors.append(room)


func _finish_pending(cell: MacroImage, build_interiors: bool) -> void:
	var waiting: Array[GeneratedRoom] = []
	for room in cell.pending:
		var interior := interiors.interior(room) if build_interiors else interiors.cached(room)
		if interior != null:
			_paint_room(cell, interior)
		else:
			waiting.append(room)
			_want(room)
	if waiting.size() == cell.pending.size():
		return
	cell.pending = waiting
	cell.floor_texture.update(cell.floor_image)
	cell.wall_texture.update(cell.wall_image)
	cell.wall_levels.clear()


## Entered Rooms whose tiles or Passage openings reach a cell. A Room belongs to one macro cell but
## its warped border may reach into the neighbours.
func _entered_rooms_reaching(rect: Rect2i) -> Array[GeneratedRoom]:
	var out: Array[GeneratedRoom] = []
	var coord := rect.position / WorldPlan.CELL
	for y in range(coord.y - 1, coord.y + 2):
		for x in range(coord.x - 1, coord.x + 2):
			var macro: MacroCellGraph = graph.cells.get(Vector2i(x, y))
			if macro == null:
				continue
			for room in macro.rooms:
				if entered_rooms.has(room.key()) and _room_reach(room).intersects(rect):
					out.append(room)
	return out


## Paints a Room's floor, walls and rocks, then the stubs its Passage openings put in fogged Rooms.
## The interior built those openings already, so the stubs cost only their tiles.
func _paint_room(cell: MacroImage, interior: RoomInterior) -> void:
	var room := interior.room
	var presentation := _finite_presentation(room)
	if presentation == null:
		return
	var floor_color := presentation.map_floor_color
	var wall_color := presentation.map_wall_color
	var area := interior.rect.intersection(cell.rect)
	var classes := interior.classes
	var width := interior.rect.size.x
	for y in range(area.position.y, area.end.y):
		var row := (y - interior.rect.position.y) * width - interior.rect.position.x
		var ly := y - cell.rect.position.y
		for x in range(area.position.x, area.end.x):
			var cls := classes[row + x]
			if cls == RoomInterior.OUTSIDE:
				continue
			cell.floor_image.set_pixel(x - cell.rect.position.x, ly, floor_color)
			if cls != RoomInterior.FLOOR:
				cell.wall_image.set_pixel(x - cell.rect.position.x, ly, wall_color)
	for passage in room.passages:
		if not WorldInteriors.opening_bounds(passage).intersects(cell.rect):
			continue
		for tile: Vector2i in interiors.opening(passage):
			if not cell.rect.has_point(tile):
				continue
			var owner := interiors.owner_at(tile)
			if owner != null and owner != room and not entered_rooms.has(owner.key()):
				cell.floor_image.set_pixelv(tile - cell.rect.position, floor_color)


## Everything a Room can own, as RoomInterior bounds it.
func _room_rect(room: GeneratedRoom) -> Rect2i:
	var low := Vector2(INF, INF)
	var high := -low
	for point in room.polygon:
		low = low.min(point)
		high = high.max(point)
	var raw := Rect2i(Vector2i(low.floor()), Vector2i((high - low).ceil()) + Vector2i.ONE)
	return raw.grow(ceili(graph.warp_bound(raw)) + 2)


## A Room's bounds with its Passage openings, which reach into the neighbours.
func _room_reach(room: GeneratedRoom) -> Rect2i:
	var reach := _room_rect(room)
	for passage in room.passages:
		reach = reach.merge(WorldInteriors.opening_bounds(passage))
	return reach


func _macro_wall_texture(cell: MacroImage, tpp: int) -> ImageTexture:
	if tpp <= 1:
		return cell.wall_texture
	if cell.wall_levels.has(tpp):
		return cell.wall_levels[tpp]
	var size := Vector2i(_ceil_div(cell.rect.size.x, tpp), _ceil_div(cell.rect.size.y, tpp))
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var floors := cell.floor_image.get_data()
	var walls := cell.wall_image.get_data()
	var width := cell.rect.size.x
	for by in size.y:
		for bx in size.x:
			var known := 0
			var wall_count := 0
			var wall_at := -1
			for y in range(by * tpp, mini((by + 1) * tpp, cell.rect.size.y)):
				for x in range(bx * tpp, mini((bx + 1) * tpp, width)):
					var alpha := (y * width + x) * 4 + 3
					if floors[alpha] > 0:
						known += 1
						if walls[alpha] > 0:
							wall_count += 1
							wall_at = alpha - 3
			if known > 0 and wall_count * 2 >= known:
				image.set_pixel(bx, by, Color8(walls[wall_at], walls[wall_at + 1], walls[wall_at + 2], walls[wall_at + 3]))
	var texture := ImageTexture.create_from_image(image)
	cell.wall_levels[tpp] = texture
	return texture


func _finite_markers() -> Array:
	var out: Array = []
	for room in graph.room_list:
		var key := room.key()
		var entered := entered_rooms.has(key)
		if room.role == GeneratedRoom.Role.BOSS and (entered or revealed_bosses.has(key)) \
				and not _boss_defeated(key):
			out.append({"tile": graph.tile_of(room.seed), "kind": MARKER_BOSS, "room_key": key,
					"project": revealed_bosses.has(key) and not entered})
		if not entered:
			continue
		for site in room.sites:
			var kind := _marker_kind(site)
			if kind >= 0:
				out.append({"tile": site.spot, "kind": kind, "room_key": key, "object_key": site.key,
						"project": false})
	return out


func _marker_kind(site: ObjectSite) -> int:
	match site.kind:
		ObjectSite.Kind.SIGN:
			return MARKER_SIGN
		ObjectSite.Kind.PROFESSOR:
			return MARKER_NPC
		ObjectSite.Kind.DOOR:
			return MARKER_DOOR
		ObjectSite.Kind.LANDING:
			return -1
		ObjectSite.Kind.WEIGHTED:
			if site.scene == null:
				return -1
			if not _scene_marker_kinds.has(site.scene):
				var node := site.scene.instantiate()
				_scene_marker_kinds[site.scene] = MARKER_FOUNTAIN if node is Fountain else MARKER_NPC
				node.free()
			return _scene_marker_kinds[site.scene]
	return -1


func _boss_defeated(room_key: String) -> bool:
	return defeated_keys.has(room_key) or defeated_keys.has(room_key + "/encounter/0/member/0")


func to_dict() -> Dictionary:
	if graph != null:
		return {"world_seed": world_seed, "entered_rooms": entered_rooms.keys(), "pins": pins,
				"revealed_bosses": revealed_bosses.keys()}
	return {"world_seed": world_seed, "discovered": discovered.keys(), "pins": pins,
			"revealed": revealed}


func restore(dict: Dictionary) -> void:
	if graph != null:
		for key in dict.get("entered_rooms", []):
			if graph.rooms.has(String(key)):
				entered_rooms[String(key)] = true
		pins.clear()
		for pin in dict.get("pins", []):
			pins.append(pin)
		for key in dict.get("revealed_bosses", []):
			reveal_boss_room(String(key))
		_macro_images.clear()
		return
	var ss: int = _streamer.config.room_slot_tiles
	for slot in dict.get("discovered", []):
		discover_at(slot * ss)
	pins.clear()
	for pin in dict.get("pins", []):
		pins.append(pin)
	for slot in dict.get("revealed", []):
		reveal_boss(slot)


func wall_texture_for(tpp: int) -> ImageTexture:
	if _wall_levels.has(tpp):
		return _wall_levels[tpp]["tex"]
	return wall_texture


func _paint_legacy_room(room: RoomOutput) -> void:
	var pres := _legacy_presentation_for(room.biome_id)
	var ss := _streamer.config.room_slot_tiles
	var ox := room.origin_slot.x * ss
	var oy := room.origin_slot.y * ss
	for y in room.height:
		for x in room.width:
			var cls := room.tile_grid[y * room.width + x]
			_floor_img.set_pixel(ox + x, oy + y, pres.map_floor_color)
			if cls == RoomBuilder.WALL or cls == RoomBuilder.BLOCKER:
				_wall_img.set_pixel(ox + x, oy + y, pres.map_wall_color)
	if room.type_id in BOSS_TYPES:
		_mark_legacy_boss(room.origin_slot, Vector2i(ox + (room.width >> 1), oy + (room.height >> 1)))
	for spawn in room.spawns:
		if spawn is Dictionary and spawn.has("feature") and not (spawn.get("feature_data") is SignDef):
			var tile: Vector2i = spawn.get("tile", Vector2i.ZERO)
			var kind := MARKER_FOUNTAIN if spawn["feature"] in _FOUNTAIN_SCENES else MARKER_FEATURE
			_legacy_markers.append({"tile": Vector2i(ox + tile.x, oy + tile.y), "kind": kind})


func _update_legacy_wall_levels(rx: int, ry: int, rw: int, rh: int) -> void:
	for tpp: int in _wall_levels:
		var img: Image = _wall_levels[tpp]["img"]
		@warning_ignore_start("integer_division")
		var bx0: int = rx / tpp
		var by0: int = ry / tpp
		@warning_ignore_restore("integer_division")
		for by in range(by0, _ceil_div(ry + rh, tpp)):
			for bx in range(bx0, _ceil_div(rx + rw, tpp)):
				var known := 0
				var walls := 0
				var wall_color := Color.TRANSPARENT
				for ty in range(by * tpp, mini((by + 1) * tpp, world_tiles.y)):
					for tx in range(bx * tpp, mini((bx + 1) * tpp, world_tiles.x)):
						if _floor_img.get_pixel(tx, ty).a > 0.0:
							known += 1
							var color := _wall_img.get_pixel(tx, ty)
							if color.a > 0.0:
								walls += 1
								wall_color = color
				if known > 0 and walls * 2 >= known:
					img.set_pixel(bx, by, wall_color)
				else:
					img.set_pixel(bx, by, Color.TRANSPARENT)


func _finite_presentation(room: GeneratedRoom) -> BiomePresentation:
	if room == null:
		return null
	return graph.plan.content.biomes[room.plan.biome].presentation


func _legacy_presentation_for(biome_id: StringName) -> BiomePresentation:
	var biome := _streamer.config.biome_by_id(biome_id)
	if biome != null and biome.presentation != null:
		return biome.presentation
	var fallback := _streamer.config.biome_by_id(_streamer.config.starting_biome)
	return fallback.presentation if fallback != null else null


static func _ceil_div(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	return (a + b - 1) / b
