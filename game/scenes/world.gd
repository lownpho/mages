extends Node2D

## Untick to leave the scene empty instead of streaming a world into it.
@export var generate_world := true
@export var world_seed := 0          # 0 = random each run, captured once for the session

## A random tier-1 weapon (rolled fresh each new game) and the heal spell are dropped next
## to the player on a brand-new run — the whole starter kit, no tutorial.
const STARTER_WEAPONS := [
	preload("res://characters/player/weapons/rune/rune1.tres"),
	preload("res://characters/player/weapons/staff/staff1.tres"),
	preload("res://characters/player/weapons/wand/wand1.tres"),
]
const STARTER_HEAL := preload("res://characters/player/spells/heal/heal1.tres")

@onready var _streamer: WorldStreamer = $WorldRoot/WorldStreamer
@onready var _player: Node2D = $WorldRoot/Entities/Player

func _ready() -> void:
	if not generate_world:
		return
	# The title screen chooses the seed (New rolls one, Continue loads the saved one).
	# Fall back to the scene's own seed when a game scene is launched directly.
	var chosen_seed := GameState.active_seed
	if chosen_seed == 0:
		chosen_seed = world_seed if world_seed != 0 else randi()
		GameState.active_seed = chosen_seed
	# Reaching the world commits the run to the save.
	GameState.persist()
	_streamer.build_world(chosen_seed)
	# Deterministic spawn: the fallback-type room nearest the starting biome's center.
	_player.global_position = _streamer.find_spawn_position()
	# Relay onto the game-wide bus: worldgen stays self-contained, game systems
	# (bestiary) listen on GlobalEvent.
	_streamer.biome_entered.connect(GlobalEvent.biome_entered.emit)
	_streamer.target = _player
	GlobalEvent.world_ready.emit(_streamer)

	if GameState.fresh_start:
		GameState.fresh_start = false
		_drop_starter_gear()

# Roll a random tier-1 weapon from the loot facility and drop it plus the heal beside the
# player, using the same loot_dropped path enemies use (GlobalPickups makes the pickups).
func _drop_starter_gear() -> void:
	var table := LootTable.new()
	for weapon in STARTER_WEAPONS:
		var drop := LootDrop.new()
		drop.item = weapon
		table.entries.append(drop)
	var origin := _player.global_position
	GlobalEvent.loot_dropped.emit(table.pick(), origin + Vector2(20, 0))
	GlobalEvent.loot_dropped.emit(STARTER_HEAL, origin + Vector2(-20, 0))
