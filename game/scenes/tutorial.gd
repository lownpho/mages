extends Node2D
## Hand-authored starting glade — a movement tutorial the player always begins in. A long
## space painted in code (so the whole layout lives in one place) that snakes right then
## upward: a spawn room, a long corridor holding a random tier-1 weapon, a room with a
## single sproutling that always drops a heal spell, a gate that only opens once that
## sproutling dies, then an upward corridor to the exit. Reaching the exit hands off to the
## procedural overworld (res://scenes/world.tscn), which generates itself and places its
## own player. Persistent state (inventory, equipment) survives via GlobalInventory.

const SproutlingScene := preload("res://characters/enemies/sproutling/sproutling.tscn")
const HealSpell := preload("res://characters/player/spells/heal/heal1.tres")
const OVERWORLD := "res://scenes/world.tscn"

# The corridor weapon is rolled from this pool of tier-1 weapons.
const TIER1_WEAPONS := [
	preload("res://characters/player/weapons/wand/wand1.tres"),
	preload("res://characters/player/weapons/staff/staff1.tres"),
	preload("res://characters/player/weapons/rune/rune1.tres"),
]

# Interior (floor) footprints in tile space; walls are auto-ringed around their union. The
# path runs bottom-left -> right along CORRIDOR_H -> the sproutling in ROOM_B -> up through
# CORRIDOR_V (sealed by GATE until the sproutling dies) -> ROOM_EXIT at the top.
const ROOM_A := Rect2i(2, 30, 14, 14)      # player spawn (bottom-left)
const CORRIDOR_H := Rect2i(16, 35, 24, 4)  # long horizontal run; holds the weapon pickup
const ROOM_B := Rect2i(40, 28, 18, 18)     # sproutling room
const CORRIDOR_V := Rect2i(46, 6, 4, 22)   # upward run to the exit
const ROOM_EXIT := Rect2i(44, 1, 8, 6)     # exit chamber at the top
const ROOMS := [ROOM_A, CORRIDOR_H, ROOM_B, CORRIDOR_V, ROOM_EXIT]

# One-tile-thick wall sealing CORRIDOR_V's mouth where it meets ROOM_B — repainted to floor
# when the sproutling dies, opening the way up.
const GATE := Rect2i(46, 27, 4, 1)

@onready var _floor: TileMapLayer = $floor
@onready var _enemies: Node2D = $Entities/Enemies
@onready var _pickups: Node2D = $Entities/pickups

var _pickup_spawner: PickupSpawner

func _ready() -> void:
	_pickup_spawner = PickupSpawner.new()
	_pickup_spawner.container = _pickups
	add_child(_pickup_spawner)
	_paint_rooms()
	_place_player(ROOM_A.get_center())
	_pickup_spawner.spawn(TIER1_WEAPONS[randi() % TIER1_WEAPONS.size()], _tile_to_world(CORRIDOR_H.get_center()))
	_spawn_sproutling(ROOM_B.get_center())
	_spawn_exit(ROOM_EXIT.get_center())

# Floor = union of the footprints; walls = every cell touching a floor cell that isn't itself
# floor. Walls are painted first then floor — matching the overworld generator so the
# floor/wall terrains autotile their shared edge. The gate is stamped last, as wall on top of
# what would otherwise be open floor, sealing the upward corridor until the sproutling dies.
func _paint_rooms() -> void:
	var floor_cells: Array[Vector2i] = []
	var floor_set := {}
	for r in ROOMS:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var cell := Vector2i(x, y)
				floor_cells.append(cell)
				floor_set[cell] = true

	var wall_cells: Array[Vector2i] = []
	var seen := {}
	for c in floor_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				if floor_set.has(n) or seen.has(n):
					continue
				seen[n] = true
				wall_cells.append(n)

	_floor.set_cells_terrain_connect(wall_cells, 0, 1, false)   # terrain set 0, wall terrain 1
	_floor.set_cells_terrain_connect(floor_cells, 0, 0, false)  # terrain set 0, floor terrain 0
	_floor.set_cells_terrain_connect(_gate_cells(), 0, 1, false)

func _gate_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(GATE.position.y, GATE.end.y):
		for x in range(GATE.position.x, GATE.end.x):
			cells.append(Vector2i(x, y))
	return cells

func _place_player(tile: Vector2i) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = _tile_to_world(tile)

func _spawn_sproutling(tile: Vector2i) -> void:
	var sprout := SproutlingScene.instantiate()
	# Override the drop table for the tutorial: guarantee the heal spell and nothing else.
	# Duplicate keeps the creature's canonical max_health; only the drops list is swapped.
	var sheet: CreatureResource = sprout.data.duplicate()
	var heal_drop := LootDrop.new()
	heal_drop.item = HealSpell
	heal_drop.chance = 1.0
	var drops: Array[LootDrop] = [heal_drop]
	sheet.drops = drops
	sprout.data = sheet
	sprout.global_position = _tile_to_world(tile)
	# The creature frees itself on death; that's our cue to open the gate.
	sprout.tree_exited.connect(_open_gate)
	_enemies.add_child(sprout)

# Repaint the gate row as floor so the floor/wall edges re-autotile into an open doorway.
func _open_gate() -> void:
	_floor.set_cells_terrain_connect(_gate_cells(), 0, 0, false)

func _spawn_exit(tile: Vector2i) -> void:
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 16  # Player physics layer
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2.ONE * GameConstants.PX_PER_TILE
	shape.shape = rect
	area.add_child(shape)
	area.global_position = _tile_to_world(tile)
	area.body_entered.connect(_on_exit_entered)
	add_child(area)

func _on_exit_entered(_body: Node2D) -> void:
	get_tree().change_scene_to_file(OVERWORLD)

# Tile centre in world pixels (mirrors GenContext.tile_to_world).
func _tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(tile * GameConstants.PX_PER_TILE) + Vector2.ONE * (GameConstants.PX_PER_TILE / 2.0)
