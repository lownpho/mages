extends Node2D

## The tutorial floor: fifteen glade rooms — three per tier, tiers 0..4 — chained entrance to
## exit so there is exactly one way through. Hand-laid, not streamed.
##
## Deliberately save-free: no WorldStreamer, no EntitySpawner, and it never emits
## GlobalEvent.world_ready (which is what books a run on the leaderboard) or calls
## GameState.persist(). Only walking out the exit commits to a run.
##
## Layout is data, tiles are painted from the glade tilesets' own tiles, so there is no
## hand-painted tilemap in the scene file to keep in sync with the room list.

const TIERS := 5
const ROOMS_PER_TIER := 3

const ROOM_TILES := Vector2i(22, 14)    ## room interior
const ROOM_PITCH := Vector2i(34, 26)    ## room origin to room origin; the slack is corridor
const CORRIDOR_HALF := 1                ## corridor is 2 * this + 1 tiles wide
## How far the trees reach past the outermost walkable tile. Everything inside that margin and
## not walkable is tree, so the floor is one solid slab of forest with the rooms cut out of it —
## no void pockets between rooms, and none past the outer edge either. Wider than the camera's
## half-view (the 320x180 viewport is 40x22 tiles) so standing on the outermost walkable tile
## still shows trees to the horizon.
const WALL_MARGIN := 26
const DECOR_CHANCE := 0.06

const SIGN_SCENE := preload("res://worldgen/runtime/under_construction_sign.tscn")

@onready var _floor: TileMapLayer = $Floor
@onready var _decor: TileMapLayer = $Decor
@onready var _walls: TileMapLayer = $Entities/Walls
@onready var _player: Node2D = $Entities/Player
@onready var _signs: Node2D = $Entities/Signs
@onready var _entrance: Door = $Entities/EntranceDoor
@onready var _exit: Door = $Entities/ExitDoor

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0x7071A11   # cosmetic only; a fixed seed keeps the tutorial identical every visit

	var rooms := _room_rects()
	_paint(_carve(rooms))
	_place_props(rooms)

	# Loaded by path rather than held as an ext_resource: the title scene points at THIS one, and
	# a static reference back would make the pair a cyclic scene dependency.
	_entrance.target_scene = load("res://scenes/title.tscn")

	# Walking out the exit is what starts the actual run, so it needs the same fresh state the
	# title's NEW button sets up (a seed, and the fresh_start flag world.gd reads to hand over
	# the starter kit). Guarded on the exit's own target so backing out the entrance — which is
	# also a scene change — leaves an existing save alone.
	SceneManager.scene_changing.connect(func(target: PackedScene) -> void:
		if target == _exit.target_scene:
			GameState.new_game())


# --- Layout -------------------------------------------------------------------------------------

## Room rects in walk order: a serpentine down the grid, one row per tier. Consecutive rooms are
## therefore always grid neighbours, so a single straight corridor joins each pair and the floor
## has no branches — one entrance, one exit, one path.
func _room_rects() -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for tier in TIERS:
		for i in ROOMS_PER_TIER:
			var col := i if tier % 2 == 0 else ROOMS_PER_TIER - 1 - i
			rects.append(Rect2i(Vector2i(col, tier) * ROOM_PITCH, ROOM_TILES))
	return rects


## The walkable tile set: every room, plus a corridor from each room's centre to the next.
func _carve(rooms: Array[Rect2i]) -> Dictionary:
	var walkable := {}
	for r in rooms:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				walkable[Vector2i(x, y)] = true
	for i in rooms.size() - 1:
		_carve_corridor(walkable, rooms[i].get_center(), rooms[i + 1].get_center())
	return walkable


# Always axis-aligned (see _room_rects), so one step vector walks it and its perpendicular
# thickens it.
func _carve_corridor(walkable: Dictionary, from: Vector2i, to: Vector2i) -> void:
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var across := Vector2i(absi(step.y), absi(step.x))
	var at := from
	while at != to:
		at += step
		for w in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
			walkable[at + across * w] = true


# --- Tiles --------------------------------------------------------------------------------------

func _paint(walkable: Dictionary) -> void:
	var floor_pick := _palette(_floor)
	var wall_pick := _palette(_walls)
	var decor_pick := _palette(_decor)

	var bounds := Rect2i()
	var first := true
	for cell: Vector2i in walkable:
		bounds = Rect2i(cell, Vector2i.ONE) if first else bounds.expand(cell)
		first = false
	bounds = bounds.grow(WALL_MARGIN)

	# Floor goes down everywhere, trees included: the tree art is transparent around its trunk,
	# so a bare wall band would show void between the trunks.
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			_place(_floor, cell, floor_pick)
			if not walkable.has(cell):
				_place(_walls, cell, wall_pick)
			elif _rng.randf() < DECOR_CHANCE:
				_place(_decor, cell, decor_pick)


## Every tile of a tileset's first source with its authored probability — the same "the art picks
## come from the tileset, not a curated list" rule the streamer follows, so adding a variant to a
## glade tileset shows up here with no code change.
func _palette(layer: TileMapLayer) -> Dictionary:
	var ts := layer.tile_set
	if ts == null or ts.get_source_count() == 0:
		return {}
	var source_id := ts.get_source_id(0)
	var src := ts.get_source(source_id) as TileSetAtlasSource
	if src == null:
		return {}
	var coords: Array[Vector2i] = []
	var weights := PackedFloat32Array()
	var total := 0.0
	for i in src.get_tiles_count():
		var c := src.get_tile_id(i)
		var td := src.get_tile_data(c, 0)
		var w := 1.0 if td == null else td.probability
		if w <= 0.0:
			continue
		coords.append(c)
		weights.append(w)
		total += w
	if coords.is_empty():
		return {}
	return {"source_id": source_id, "coords": coords, "weights": weights, "total": total}


func _place(layer: TileMapLayer, cell: Vector2i, pick: Dictionary) -> void:
	if pick.is_empty():
		return
	var coords: Array[Vector2i] = pick.coords
	var weights: PackedFloat32Array = pick.weights
	var r: float = _rng.randf() * float(pick.total)
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			layer.set_cell(cell, int(pick.source_id), coords[i])
			return
	layer.set_cell(cell, int(pick.source_id), coords[coords.size() - 1])


# --- Props --------------------------------------------------------------------------------------

## One sign per room naming its tier, the player and the way back in the first room, the way out
## in the last.
func _place_props(rooms: Array[Rect2i]) -> void:
	for i in rooms.size():
		@warning_ignore("integer_division")
		var tier := i / ROOMS_PER_TIER
		var marker: UnderConstructionSign = SIGN_SCENE.instantiate()
		marker.message = "TIER %d" % tier
		marker.position = _to_px(rooms[i].get_center() + Vector2i(0, -3))
		_signs.add_child(marker)

	_entrance.position = _to_px(rooms[0].get_center() + Vector2i(-5, 0))
	_player.global_position = _to_px(rooms[0].get_center() + Vector2i(-1, 3))
	_exit.position = _to_px(rooms[rooms.size() - 1].get_center() + Vector2i(5, 0))


static func _to_px(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
