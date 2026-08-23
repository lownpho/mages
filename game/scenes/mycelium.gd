extends Node2D

## The mycelium dungeon: the floors its GenConfig stacks, a seed apiece, entered through the mimic
## deepwood's mushroom door. Every floor carries exactly two stairs — one up, one down, pinned room
## types at opposite ends of its difficulty ramp — and walking into one rebuilds the streamer on the
## neighbouring floor's seed. A floor change is NOT a scene change: this one scene is the whole
## descent, which is why the floor lives in a var and never in the save.
##
## Both ends of the ladder lead back out: up from floor 1 and down from the last floor drop the
## player back on the mushroom door they came in by (world.gd stashes where they stood). The depth
## and the stair room ids are the config's (see GenConfig's Dungeon group) — nothing here counts.

## Loaded rather than preloaded: the overworld's config reaches this scene through the mushroom
## door's DoorResource, so a preload here would close a resource cycle.
const OVERWORLD := "res://scenes/world.tscn"

@onready var _streamer: WorldStreamer = $WorldRoot/WorldStreamer
@onready var _player: Node2D = $WorldRoot/Entities/Player

var _floor := 1
var _overworld_map: Dictionary = {}


func _ready() -> void:
	# The overworld's discovered map is still the live one until we build over it; hand it back on
	# the way out, so a trip down here doesn't re-fog everything the player had already walked.
	_overworld_map = GlobalMap.to_dict()
	_streamer.biome_entered.connect(GlobalEvent.biome_entered.emit)
	GlobalEvent.floor_change_requested.connect(_on_floor_change)
	_streamer.target = _player
	_enter_floor(1, _streamer.config.stair_up_room)


func _on_floor_change(delta: int, _body: Node2D) -> void:
	var n := DungeonFloors.next_floor(_streamer.config, _floor, delta)
	if n == 0:
		GlobalMap.restore(_overworld_map)
		SceneManager.go_to(load(OVERWORLD))
		return
	# Arriving on a floor means arriving at the stair you did NOT take: descending lands at the
	# next floor's up stair, climbing at the previous floor's down stair.
	_enter_floor(n, _streamer.config.stair_up_room if delta > 0 else _streamer.config.stair_down_room)


# One floor = one seed: rooms, stairs and (once they exist) enemies all fall out of the generator,
# so a floor costs a rebuild and nothing else. The streamer frees the old floor's chunks — and
# with them its enemies — before the new one streams in.
func _enter_floor(n: int, arrive_at: StringName) -> void:
	_floor = n
	_streamer.build_world(DungeonFloors.floor_seed(GameState.active_seed, n))
	_player.global_position = DungeonFloors.stair_position(_streamer, arrive_at)
	GlobalMap.rebuild(_streamer)   # each floor is its own space: own fog, own textures
