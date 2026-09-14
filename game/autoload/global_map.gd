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
signal pins_changed  ## a pin was dropped or removed, or a sign marked a boss — non-frame-driven views redraw, save persists
signal boss_revealed(room_key: String)  ## an Object revealed a finite-World Boss Room for the first time this Run
signal discovery_changed(entered_rooms: Dictionary) ## a finite-World Room was entered

var active: MapState = null
## Finite-World Boss Room keys revealed this Run. The Room-key Map shows and saves them.
var revealed_boss_keys: Dictionary[String, bool] = {}

var _streamer: WorldStreamer = null
var _player: Node2D = null
var _last_tile := Vector2i(-1, -1)
## Discovered slots stashed by restore() before the world exists (Continue loads the save on the
## title screen, before world.tscn), applied once world_ready builds the state.
var _pending_restore: Dictionary = {}


func _ready() -> void:
	GlobalEvent.world_ready.connect(rebuild)
	set_process(false)


## Point the map at a streamer's world: a fresh, fully fogged state (any pending restore applied
## on top). The overworld arrives here through world_ready; a dungeon floor calls it directly on
## every rebuild, each floor being its own space with its own fog.
func rebuild(streamer: WorldStreamer) -> void:
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


## Point the Map at the finite generator while both generators coexist. preserve_records is used by
## a debug knob rebuild: Room/Object keys follow place, so the same records remain meaningful.
func rebuild_finite(streamer: ChunkStreamer, defeated_keys: Dictionary = {},
		preserve_records := false) -> void:
	var records := active.to_dict() if preserve_records and active != null \
			and active.is_finite_world() else _pending_restore
	_streamer = null
	active = MapState.new()
	active.setup_finite(streamer.graph, streamer.interiors, defeated_keys)
	if not records.is_empty():
		active.restore(records)
	_pending_restore = {}
	# A Sign can reveal through the global contract before the Map is built.
	for room_key in revealed_boss_keys:
		active.reveal_boss_room(room_key)
	_player = get_tree().get_first_node_in_group("player")
	_last_tile = Vector2i(-1, -1)
	set_process(true)
	map_changed.emit()
	discovery_changed.emit(active.entered_rooms)


## Fog-of-war discovery is model logic, so it lives here (not in the minimap widget) — the map
## keeps filling in even while the minimap is hidden or the full map is open.
func _process(_dt: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var tile := Vector2i((_player.global_position / GameConstants.PX_PER_TILE).floor())
	if tile != _last_tile:
		_last_tile = tile
		discover_at(tile)


## Public entry seam used by Warp arrivals as well as walking.
func discover_at(tile: Vector2i) -> bool:
	if active == null or not active.discover_at(tile):
		return false
	if active.is_finite_world():
		discovery_changed.emit(active.entered_rooms)
	return true


## Toggle a pin at a world tile: remove one already within `remove_radius_tiles`, else drop a new
## one. This is the whole pin UI contract — the minimap and the full map both just call this.
func toggle_pin(world_tile: Vector2i, remove_radius_tiles: int) -> void:
	if active == null:
		return
	if not active.remove_pin_near(world_tile, remove_radius_tiles):
		active.add_pin(world_tile)
	pins_changed.emit()


## Mark a boss room on the active map before it is found: the player read a sign pointing at it.
## Only a marker that wasn't there yet counts as a change, so walking past the same sign again
## doesn't rewrite the save.
func reveal_boss(origin_slot: Vector2i) -> void:
	if active != null and active.reveal_boss(origin_slot):
		pins_changed.emit()


## Reveals a planned Boss Room of the finite World before it is found. Any Object may call it;
## Signs are the authored source. Revealing the same Room again changes nothing.
func reveal_boss_room(room_key: String) -> void:
	if room_key == "" or revealed_boss_keys.has(room_key):
		return
	if active != null and active.is_finite_world() and not active.reveal_boss_room(room_key):
		return
	revealed_boss_keys[room_key] = true
	boss_revealed.emit(room_key)
	pins_changed.emit()


## Minimal save payload for the whole map. Empty when no world is active yet.
func to_dict() -> Dictionary:
	return active.to_dict() if active != null else {}


## Feed a saved payload back in. Called by GameState on Continue, always before the new world
## scene loads — the state that will hold it doesn't exist yet (and any lingering `active` from a
## prior run points at a freed streamer), so we only stash; world_ready builds a fresh MapState
## and applies this then.
func restore(dict: Dictionary) -> void:
	_pending_restore = dict
	revealed_boss_keys.clear()
	for room_key in dict.get("revealed_bosses", []):
		revealed_boss_keys[String(room_key)] = true


## Drop all discovered map state — a fresh run starts fully fogged.
func reset() -> void:
	active = null
	revealed_boss_keys.clear()
	_pending_restore = {}
	_last_tile = Vector2i(-1, -1)
	set_process(false)
