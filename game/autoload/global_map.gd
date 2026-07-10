extends Node

## The live run's discovered-world model ("the map"), shared by the strip minimap and the
## full-screen map and persisted in the save. Owns the active MapState, drives fog-of-war
## discovery from the player's position each frame, and (re)builds deterministically from the
## world seed + discovered slots — so the whole map is restored from a tiny payload (see
## GameState).
##
## Today there is a single overworld space. Multi-floor dungeons will turn this into a book of
## spaces (one MapState each, keyed by space id) with the minimap always showing the active one;
## the ownership already lives here, at autoload scope, precisely so it survives the scene swap
## into a dungeon.

signal map_changed   ## active MapState was (re)built or swapped — views re-bind on this

var active: MapState = null

var _streamer: WorldStreamer = null
var _player: Node2D = null
var _last_tile := Vector2i(-1, -1)
## Discovered slots stashed by restore() before the world exists (Continue loads the save on the
## title screen, before world.tscn), applied once world_ready builds the state.
var _pending_restore: Dictionary = {}


func _ready() -> void:
	GlobalEvent.world_ready.connect(_on_world_ready)
	set_process(false)


func _on_world_ready(streamer: WorldStreamer) -> void:
	_streamer = streamer
	active = MapState.new()
	active.setup(streamer, MapState.ZOOM_TILES_PER_PX)
	if not _pending_restore.is_empty():
		active.restore(_pending_restore)
		_pending_restore = {}
	_player = get_tree().get_first_node_in_group("player")
	_last_tile = Vector2i(-1, -1)
	set_process(true)
	map_changed.emit()


## Fog-of-war discovery is model logic, so it lives here (not in the minimap widget) — the map
## keeps filling in even while the minimap is hidden or the full map is open.
func _process(_dt: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var tile := Vector2i((_player.global_position / GameConstants.PX_PER_TILE).floor())
	if tile != _last_tile:
		_last_tile = tile
		active.discover_at(tile)


## Minimal save payload for the whole map. Empty when no world is active yet.
func to_dict() -> Dictionary:
	return active.to_dict() if active != null else {}


## Feed a saved payload back in. Called by GameState on Continue, always before the new world
## scene loads — the state that will hold it doesn't exist yet (and any lingering `active` from a
## prior run points at a freed streamer), so we only stash; world_ready builds a fresh MapState
## and applies this then.
func restore(dict: Dictionary) -> void:
	_pending_restore = dict


## Drop all discovered map state — a fresh run starts fully fogged.
func reset() -> void:
	active = null
	_pending_restore = {}
	_last_tile = Vector2i(-1, -1)
	set_process(false)
