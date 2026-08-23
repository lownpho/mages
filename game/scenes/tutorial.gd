extends Node2D

## The tutorial floor: a chain of glade rooms laid entrance to exit, so there is exactly one way
## through. Hand-laid, not streamed.
##
## PROGRESSION is the whole running order and the one thing to edit: entry i IS the i-th room the
## player walks into, so the array reads top to bottom the way the tutorial plays. Reorder it to
## reorder the tutorial; add an entry and the floor grows a room to hold it.
##
## Deliberately save-free: no WorldStreamer, no EntitySpawner, and it never emits
## GlobalEvent.world_ready (which is what books a run on the leaderboard) or calls
## GameState.persist(). Only walking out the exit commits to a run.
##
## Layout is data, tiles are painted from the glade tilesets' own tiles, so there is no
## hand-painted tilemap in the scene file to keep in sync with the room list.

## The running order, entrance first, exit last. Each entry is what that room's sign says; an
## empty entry is a room with nothing to teach yet, and gets no sign at all.
const PROGRESSION: Array[String] = [
	"",   # entrance: its sign is INTRO_SIGN, which stands at the spawn instead of the centre
	"""Spells lie on the ground here. Walk over one to pick it up.
A robe will not take a spell it already holds.""",
	"""You cast spells with LEFT, MIDDLE, RIGHT MOUSE and SPACE.
On a pad: L1, L2, R1 and R2. Try it.""",
	"""You cast where you aim: at the mouse, or with the right stick.
With no stick held, you cast the way you are running.""",
	"""You have 3 robes but you can only wear one at a time.
Switch robe with SHIFT, or Y on a pad.
Drag and drop spells between robes, or across slots of one robe.
On a pad: START for the slots, A to lift a spell, A again to place.""",
	"""Robes and spells change what you are made of.
Watch the numbers on the left.
Some will suit you better than others.""",
	"""The bar on the left is your life. Enemies take it from you.
Lose all of it and your run ends here.""",
	"A vicious enemy. Kill it before it kills you.",
	"""Step into the fountain to be made whole again.
It runs dry for a while after.""",
	"""You will not want every spell you find.
Drag one off the slots and drop it to throw it away.
Q does the same, or X on a pad.""",
	"""Through this door the real thing begins.
Good luck.""",
]


## Grid width. Only shapes where the chain folds on screen — the running order is PROGRESSION's,
## whatever this is. A short final row is fine.
const ROOMS_PER_ROW := 3

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

## The one message that has to land before the player knows how to walk up to anything, so its
## sign stands where they spawn rather than waiting to be found. Hand-broken: the sign's label
## doesn't wrap, and two lines is the box it was drawn for.
const INTRO_SIGN := """You move with W A S D or the left analog stick.
Go in the next room to learn your first spells"""

const SIGN_SCENE := preload("res://worldgen/runtime/under_construction_sign.tscn")

## The starter kit, dropped on the floor of the casting room so the player has spells in hand by
## the time that room's sign explains the cast buttons — a run entered from the title never
## called GameState.new_game(), so the loadout arrives empty. Read off world.gd rather than
## relisted: one starter kit, not two that can drift apart.
const STARTER_SPELLS := preload("res://scenes/world.gd").STARTER_SPELLS
const STARTER_ROOM := 1

## The first fight, and the room it waits in. Asleep until it is on screen (the scene carries
## the usual off-screen sleeper), so it does not wander up the corridor to meet the player.
const FIRST_FIGHT := preload("res://characters/enemies/sproutling/sproutling.tscn")
const FIRST_FIGHT_ROOM := 7

## The heal, one room past the fight — the player arrives having just spent health on it.
const FOUNTAIN := preload("res://worldgen/runtime/glade_fountain.tscn")
const FOUNTAIN_ROOM := 8

@onready var _floor: TileMapLayer = $Floor
@onready var _decor: TileMapLayer = $Decor
@onready var _walls: TileMapLayer = $Entities/Walls
@onready var _player: Node2D = $Entities/Player
@onready var _signs: Node2D = $Entities/Signs
@onready var _enemies: Node2D = $Entities/Enemies
@onready var _entities: Node2D = $Entities
@onready var _exit: Door = $Entities/ExitDoor

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Nothing in here is a run. The player can reach the tutorial with a real save already on
	# disk, so every write is suppressed for as long as this scene is alive — see
	# GameState.sandbox. Lifted in _exit_tree, which is the one place all three ways out meet.
	GameState.sandbox = true

	_rng.seed = 0x7071A11   # cosmetic only; a fixed seed keeps the tutorial identical every visit

	var rooms := _room_rects()
	_paint(_carve(rooms))
	_place_props(rooms)

	# Walking out the exit is what starts the actual run, so it needs the same fresh state the
	# title's NEW button sets up (a seed, and the fresh_start flag world.gd reads to hand over
	# the starter kit). Guarded on the exit's own target because it is NOT the only scene change
	# a tutorial can make: death bounces to the title through game_over(), and the HUD's quit
	# button leaves too. Neither of those may roll a fresh run.
	#
	# new_game() writes nothing itself — it rolls a seed and clears the loadout in memory — so
	# it is safe to run while the sandbox is still up. world.gd writes the first save, by which
	# point _exit_tree has lifted it.
	SceneManager.scene_changing.connect(func(target: PackedScene) -> void:
		if target == _exit.target_scene:
			GameState.new_game())


## Every way out of the tutorial lands here: the exit door, death through game_over(), and the
## HUD's quit button. Dropping the props and lifting the sandbox in one place is what keeps the
## three paths from needing to agree with each other.
func _exit_tree() -> void:
	GlobalInventory.reset()
	GameState.sandbox = false


# --- Layout -------------------------------------------------------------------------------------

## One rect per PROGRESSION entry, in that order: a serpentine down the grid, so consecutive
## rooms are always grid neighbours. A single straight corridor then joins each pair and the
## floor has no branches — one entrance, one exit, one path.
func _room_rects() -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for i in PROGRESSION.size():
		@warning_ignore("integer_division")
		var row := i / ROOMS_PER_ROW
		var at := i % ROOMS_PER_ROW
		# Odd rows run right-to-left, so the last room of a row sits directly above the first
		# room of the next and the corridor between them is a straight drop.
		var col := at if row % 2 == 0 else ROOMS_PER_ROW - 1 - at
		rects.append(Rect2i(Vector2i(col, row) * ROOM_PITCH, ROOM_TILES))
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

## A sign per room that has something to say, the player in the first room, the way out in the
## last.
func _place_props(rooms: Array[Rect2i]) -> void:
	for i in rooms.size():
		if PROGRESSION[i].is_empty():
			continue
		var marker: UnderConstructionSign = SIGN_SCENE.instantiate()
		marker.message = PROGRESSION[i]
		marker.position = _to_px(rooms[i].get_center() + Vector2i(0, -3))
		_signs.add_child(marker)

	# Second sign in the entrance room, standing inside its own trigger radius from the spawn —
	# so the movement prompt is already up on the first frame.
	var intro: UnderConstructionSign = SIGN_SCENE.instantiate()
	intro.message = INTRO_SIGN
	intro.position = _to_px(rooms[0].get_center() + Vector2i(-3, 3))
	_signs.add_child(intro)

	for i in STARTER_SPELLS.size():
		var angle := TAU * i / STARTER_SPELLS.size()
		GlobalEvent.loot_dropped.emit(STARTER_SPELLS[i],
				_to_px(rooms[STARTER_ROOM].get_center()) + Vector2(20, 0).rotated(angle))

	var foe: Node2D = FIRST_FIGHT.instantiate()
	foe.position = _to_px(rooms[FIRST_FIGHT_ROOM].get_center() + Vector2i(0, 4))
	_enemies.add_child(foe)

	var pool: Node2D = FOUNTAIN.instantiate()
	pool.position = _to_px(rooms[FOUNTAIN_ROOM].get_center() + Vector2i(0, 3))
	_entities.add_child(pool)

	_player.global_position = _to_px(rooms[0].get_center() + Vector2i(-1, 3))
	_exit.position = _to_px(rooms[rooms.size() - 1].get_center() + Vector2i(5, 0))


static func _to_px(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
