extends Node

## The Run's Map, shared by the strip minimap and the full-screen map and persisted in the save.
## Owns the active MapState, drives discovery from the player's position each frame, and rebuilds
## it from the World's graph plus the saved Room keys, Pins and revealed Bosses — so the whole Map
## is restored from a tiny payload (see GameState).

signal map_changed   ## active MapState was (re)built — views re-bind on this
signal pins_changed  ## a pin was dropped or removed, or an Object revealed a Boss — non-frame-driven views redraw, save persists
signal boss_revealed(room_key: String)  ## an Object revealed a Boss Room for the first time this Run
signal discovery_changed(entered_rooms: Dictionary) ## a Room was entered

var active: MapState = null
## Boss Room keys revealed this Run. The Map shows and saves them.
var revealed_boss_keys: Dictionary[String, bool] = {}

## The World's streamer, which builds the interiors Map views drew without.
var _chunk_streamer: ChunkStreamer = null
var _player: Node2D = null
var _last_tile := Vector2i(-1, -1)
## Map records stashed by restore() before the World exists (Continue loads the save on the title
## screen, before world.tscn), applied by the next rebuild().
var _pending_restore: Dictionary = {}


func _ready() -> void:
	set_process(false)


## Point the Map at a streamer's World: a fresh, fully fogged state with any pending restore applied.
## preserve_records is used by a debug knob rebuild: Room/Object keys follow place, so the same
## records remain meaningful.
func rebuild(streamer: ChunkStreamer, defeated_keys: Dictionary = {},
		preserve_records := false) -> void:
	var records := active.to_dict() if preserve_records and active != null else _pending_restore
	_chunk_streamer = streamer
	active = MapState.new()
	active.setup(streamer.graph, streamer.interiors, defeated_keys)
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


## Discovery is model logic, so it lives here (not in the minimap widget) — the Map keeps filling in
## even while the minimap is hidden or the full map is open.
func _process(_dt: float) -> void:
	if active != null and not active.wanted_interiors.is_empty() and is_instance_valid(_chunk_streamer):
		_chunk_streamer.request_interiors(active.take_wanted_interiors())
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


## Reveals a planned Boss Room before it is found. Any Object may call it; Signs are the authored
## source. Revealing the same Room again changes nothing, so walking past the same Sign again
## doesn't rewrite the save.
func reveal_boss_room(room_key: String) -> void:
	if room_key == "" or revealed_boss_keys.has(room_key):
		return
	if active != null and not active.reveal_boss_room(room_key):
		return
	revealed_boss_keys[room_key] = true
	boss_revealed.emit(room_key)
	pins_changed.emit()


## Minimal save payload for the whole map. Empty when no world is active yet.
func to_dict() -> Dictionary:
	return active.to_dict() if active != null else {}


## Feed a saved payload back in. Called by GameState on Continue, always before the World scene
## loads — the state that will hold it doesn't exist yet (and any lingering `active` from a prior
## Run belongs to a freed World), so we only stash; rebuild() applies it.
func restore(dict: Dictionary) -> void:
	_pending_restore = dict
	revealed_boss_keys.clear()
	for room_key in dict.get("revealed_bosses", []):
		revealed_boss_keys[String(room_key)] = true


## Drop all discovered map state — a fresh run starts fully fogged.
func reset() -> void:
	active = null
	_chunk_streamer = null
	revealed_boss_keys.clear()
	_pending_restore = {}
	_last_tile = Vector2i(-1, -1)
	set_process(false)
