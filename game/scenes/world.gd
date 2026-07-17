extends Node2D

## Untick to leave the scene empty instead of streaming a world into it.
@export var generate_world := true
@export var world_seed := 0          # 0 = random each run, captured once for the session

## The design's spawn_with kit, dropped next to the player on a brand-new run — the whole
## starter loadout, no tutorial.
const STARTER_SPELLS: Array[Resource] = [
	preload("res://characters/player/spells/fireball/fireball1.tres"),
	preload("res://characters/player/spells/heal/heal1.tres"),
	preload("res://characters/player/spells/blam/blam1.tres"),
]

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
	_streamer.build_world(chosen_seed)
	# Continue resumes exactly where the player left off; a fresh run uses the
	# deterministic spawn (the fallback-type room nearest the starting biome's center).
	if GameState.has_pending_position:
		# A save made under an older world layout can point into what is now a wall, so
		# snap the restored spot onto the nearest floor; if the layout diverged too far to
		# find any, fall back to the deterministic spawn rather than trapping the player.
		var restored := _streamer.nearest_walkable(GameState.pending_player_position)
		_player.global_position = restored if restored != Vector2.INF \
				else _streamer.find_spawn_position()
		GameState.has_pending_position = false
	else:
		_player.global_position = _streamer.find_spawn_position()
	# Spawn buffer: enemies placed near the spawn point can't chip the player before
	# they've taken control (Continue resumes mid-world, so it wants the grace too).
	_player.grant_spawn_grace()
	# Relay onto the game-wide bus: worldgen stays self-contained, game systems
	# (bestiary) listen on GlobalEvent.
	_streamer.biome_entered.connect(GlobalEvent.biome_entered.emit)
	_streamer.target = _player
	GlobalEvent.world_ready.emit(_streamer)

	# Reaching the world (with the player placed) commits the run to the save, and
	# arms the periodic position autosave.
	GameState.track_player(_player)
	GameState.persist()

	if GameState.fresh_start:
		GameState.fresh_start = false
		_drop_starter_gear()

# Drop the starter spells beside the player, using the same loot_dropped path enemies
# use (GlobalPickups makes the pickups).
func _drop_starter_gear() -> void:
	var origin := _player.global_position
	for i in STARTER_SPELLS.size():
		var angle := TAU * i / STARTER_SPELLS.size()
		GlobalEvent.loot_dropped.emit(STARTER_SPELLS[i], origin + Vector2(20, 0).rotated(angle))
