extends Node2D

const GLADE := preload("res://overworld/biomes/glade/glade.tres")

## Untick to leave the scene empty instead of generating into it.
@export var generate_world := true
@export var world_seed := 0                  # 0 = random each run
@export var world_size := Vector2i(160, 120)   # tiles (bounds; the landmass fills an organic blob inside)
@export var spawn_clear_radius := 6          # tiles kept enemy-free around the player

@onready var _floor: TileMapLayer = $floor
@onready var _decor: TileMapLayer = $decor
@onready var _objects: TileMapLayer = $Entities/objects
@onready var _enemies: Node2D = $Entities/Enemies

func _ready() -> void:
	if generate_world:
		_generate_overworld()

func _generate_overworld() -> void:
	# Idempotent: clear any prior generation before painting a fresh world.
	_floor.clear()
	_decor.clear()
	_objects.clear()
	for n in _enemies.get_children():
		n.free()

	var biomes: Array[BiomeResource] = []
	biomes.append(GLADE)

	var ctx := GenContext.new()
	ctx.rng = RandomNumberGenerator.new()
	ctx.rng.seed = world_seed if world_seed != 0 else randi()
	ctx.ground = _floor
	ctx.decor = _decor
	ctx.objects = _objects
	ctx.enemies = _enemies
	ctx.bounds = Rect2i(Vector2i.ZERO, world_size)
	ctx.biomes = biomes

	WorldGenerator.new().generate(ctx)
	_place_player(ctx)

func _place_player(ctx: GenContext) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	var centre := ctx.tile_to_world(ctx.bounds.get_center())
	player.global_position = centre
	# Fixture rule: clear enemies that spawned too close to the player's start.
	var r := spawn_clear_radius * GameConstants.PX_PER_TILE
	for e in _enemies.get_children():
		if e.global_position.distance_to(centre) < r:
			e.free()
