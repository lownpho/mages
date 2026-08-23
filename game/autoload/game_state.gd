extends Node

## Minimal run persistence: the title screen picks a world seed here, every scene
## reads it back, and it survives between launches so "Continue" can resume the same
## world. A world is a pure function of its seed (see worldgen), so the seed alone
## restores the map; player position and inventory are saved alongside it so Continue
## resumes where the player left off, not just the map they were in.

const SAVE_PATH := "user://save.cfg"

## Bumped when the save shape changes incompatibly (v2: the spell-only loadout —
## no weapon/hat/robe slots, no mana). An older save simply reads as "nothing to
## continue" rather than being migrated.
const SAVE_VERSION := 0

## The world is a pure function of (seed, gen_version, CONFIG_HASH); the same seed lays out
## a different map once the generation code or config changes. We stamp the save with the
## current world signature so Continue can tell whether a stored player position still lands
## where it did — a mismatch means the layout moved under it, so the position is discarded
## and the run respawns at the deterministic spawn instead of inside what is now a wall.
const CONFIG_PATH := "res://world_content/gen_config.tres"

## One cloud save per account, mirroring user://save.cfg byte for byte. The account is
## the source of truth: a login pulls it down over the local file, every persist() pushes
## back up. Logged out, none of this runs and the local file is the whole story.
const CLOUD_SAVE_NAME := "run"

## Emitted once a login sync has settled, so a title screen already on screen can
## re-offer Continue against the account's run rather than this machine's.
signal cloud_sync_finished

## How often to resave the player's position while playing. Inventory changes persist
## immediately (they're user-driven and rare); position drifts every frame, so it's
## only snapshotted periodically instead of on every movement.
const POSITION_SAVE_INTERVAL := 4.0

## The seed for this session's world. 0 = nothing chosen yet (editor-launched a game
## scene directly), so scenes fall back to their own default.
var active_seed := 0

## True for the first world entry of a brand-new run, so world.gd can drop starter gear
## next to the player exactly once. Runtime-only (never saved); Continue leaves it false.
var fresh_start := false

## Position loaded from a Continue'd save, for world.gd to place the player at instead
## of the deterministic spawn point. Only meaningful when set by continue_game().
var pending_player_position: Vector2 = Vector2.ZERO
var has_pending_position := false

## entity_id -> true for defeated rare/boss enemies in the current world, so closing and
## reopening the game (or streaming a chunk out and back) can't refarm a one-of-a-kind
## encounter. Entity ids are a pure hash of [world_seed, room, index] (see Population),
## so they never collide across different seeds — a fresh new_game() naturally starts
## empty and stale entries from an abandoned seed are simply never matched again.
var notable_kills: Dictionary = {}

var _tracked_player: Node2D = null
var _save_timer: Timer
var _suspend_autosave := false
var _cloud: RunCloudSave = null


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.wait_time = POSITION_SAVE_INTERVAL
	_save_timer.timeout.connect(_on_autosave_tick)
	add_child(_save_timer)
	# Autosave on inventory edits, but only once a player is being tracked: persist() rebuilds
	# the save from scratch and would otherwise write a position-less save (it only stores the
	# position when a player is tracked), which Continue then reads back as (0,0). Inventory
	# changes during scene transitions — before world.gd calls track_player — are exactly that
	# window, so gate on it.
	GlobalEvent.slot_updated.connect(func(_slot: GlobalInventory.Slot) -> void:
		if not _suspend_autosave and is_instance_valid(_tracked_player):
			persist())
	# Pins are user-driven and rare (like inventory edits), so persist immediately rather than
	# waiting for the periodic tick — same tracked-player gate to avoid a position-less write.
	GlobalMap.pins_changed.connect(func() -> void:
		if not _suspend_autosave and is_instance_valid(_tracked_player):
			persist())
	GlobalEvent.leaderboard_session_changed.connect(_on_session_changed)


func has_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	# A save from an older shape is invisible: Continue never offers it.
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	return int(cfg.get_value("world", "version", 1)) == SAVE_VERSION


## Roll a fresh world in memory and start it in the glade. The save is written once the
## world scene loads (world.gd calls persist()); fresh_start flags that first entry so the
## player is handed a starter weapon and heal.
func new_game() -> void:
	active_seed = randi()
	if active_seed == 0:
		active_seed = 1  # keep 0 reserved for "unset"
	fresh_start = true
	has_pending_position = false
	notable_kills = {}
	# Fresh run: nothing carries over. The bestiary (its own autoload) is intentionally
	# left alone so kill discoveries persist across runs.
	GlobalMap.reset()
	_suspend_autosave = true
	GlobalInventory.reset()
	_suspend_autosave = false


## Load the saved seed, position, and inventory into the session. Returns false if
## there is nothing to continue.
func continue_game() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	if int(cfg.get_value("world", "version", 1)) != SAVE_VERSION:
		return false
	active_seed = int(cfg.get_value("world", "seed", 0))
	if active_seed == 0:
		return false
	pending_player_position = cfg.get_value("player", "position", Vector2.ZERO)
	# Only resume at the stored position when it's actually present AND was saved under the
	# current world layout. A missing key (a position-less save) must NOT fall back to the
	# Vector2.ZERO default — that drops the player at the world origin — and a stale signature
	# means the same seed now lays out a different map. Either way, defer to the deterministic
	# spawn (see world.gd, which also snaps a surviving position onto floor as a further guard).
	var signature_ok: bool = cfg.get_value("world", "signature", "") == _world_signature()
	has_pending_position = signature_ok and cfg.has_section_key("player", "position")
	# The discovered map is slot coords into the layout, so it only means anything under the same
	# signature; a diverged layout starts fully fogged rather than revealing the wrong rooms.
	# GlobalMap stashes this until world_ready builds the state (Continue runs before the world).
	if signature_ok:
		GlobalMap.restore(cfg.get_value("map", "state", {}))
	else:
		GlobalMap.reset()
	notable_kills = cfg.get_value("world", "notable_kills", {})
	_load_inventory(cfg)
	return true


## Record a defeated rare/boss enemy and persist immediately (rare enough that this is
## cheap, and important enough not to lose to a crash between now and the next autosave).
func record_notable_kill(entity_id: int) -> void:
	notable_kills[entity_id] = true
	persist()


## Periodic position autosave. Once the run is left (Quit to title frees the world, so the
## tracked player is gone) the timer must stop, or it would keep rewriting the save from scratch
## without a position — dropping the stored spot back to spawn while the map (read from a
## still-alive stale MapState) survives. Stopping here catches every world-exit path in one place.
func _on_autosave_tick() -> void:
	if not is_instance_valid(_tracked_player):
		_save_timer.stop()
		return
	persist()


## Called once by world.gd after placing the (possibly restored) player, so the
## periodic position autosave and immediate inventory autosave have a target.
func track_player(player: Node2D) -> void:
	_tracked_player = player
	_save_timer.start()


## True while a live run is in progress (a player is placed in the world). Loadout
## edits at the title — the Continue restore, new_game's reset — happen outside it.
func in_run() -> bool:
	return is_instance_valid(_tracked_player)


## Wipe the save so there is nothing to Continue. Called on death.
func clear_save() -> void:
	active_seed = 0
	has_pending_position = false
	_tracked_player = null
	GlobalMap.reset()
	_save_timer.stop()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	_push_cloud()


## The run ended (the player died): wipe the run — save and inventory — and return to
## the title screen. The bestiary (its own autoload) persists across runs.
func game_over() -> void:
	clear_save()
	_suspend_autosave = true
	GlobalInventory.reset()
	_suspend_autosave = false
	SceneManager.go_to(load("res://scenes/title.tscn"))


## Persist the current run so "Continue" can resume it: seed, player position (if a
## player is being tracked), and the full inventory. Called on world entry, on every
## inventory change, and periodically while playing.
func persist() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("world", "version", SAVE_VERSION)
	cfg.set_value("world", "seed", active_seed)
	cfg.set_value("world", "signature", _world_signature())
	cfg.set_value("world", "notable_kills", notable_kills)
	cfg.set_value("map", "state", GlobalMap.to_dict())
	if is_instance_valid(_tracked_player):
		cfg.set_value("player", "position", _tracked_player.global_position)
	_save_inventory(cfg)
	cfg.save(SAVE_PATH)
	_push_cloud()


# --- Cloud save ---------------------------------------------------------------
# The account holds the run; this machine holds a copy of it. Login adopts the
# account's save over the local file, and every persist() mirrors back up.


## Login — boot restore, login and register alike. The loadable can only be registered
## here and not in _ready(): Talo stamps it with the current scene's path, and an autoload
## readies before there is a current scene. A brand-new account gets this machine's run
## uploaded rather than losing it.
func _on_session_changed(logged_in: bool) -> void:
	if not logged_in:
		return
	if _cloud == null:
		_cloud = RunCloudSave.new()
		_cloud.id = CLOUD_SAVE_NAME
		add_child(_cloud)
	await Talo.saves.get_saves()
	if Talo.saves.latest != null:
		Talo.saves.choose_save(Talo.saves.latest)  # hydrates into adopt_cloud_save()
	else:
		await Talo.saves.create_save(CLOUD_SAVE_NAME)
	cloud_sync_finished.emit()


## The save file's raw text — empty when there is nothing to continue, which is itself
## worth mirroring (a death clears the account's run too).
func save_text() -> String:
	return FileAccess.get_file_as_string(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""


## Take the account's copy as the local save. Refused mid-run: a login while playing
## must not yank the world out from under the player — that run pushes up instead.
func adopt_cloud_save(text: String) -> void:
	if in_run():
		return
	if text.is_empty():
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(SAVE_PATH)
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(text)


## Mirror the local file up. Talo debounces the request and, with the network down,
## queues it into its own offline store for the next login sync — so this is as cheap
## to call as persist() itself.
func _push_cloud() -> void:
	if Talo.saves.current != null:
		Talo.saves.update_current_save()


## "gen_version:config_hash" for the authored world config — the identity of the current
## map generator. Loading the resource is cheap (Godot caches it; the streamer loads the
## same instance) and read-only. Empty string if the config can't be loaded, which simply
## never matches a stored signature, so the position guard fails safe to a fresh spawn.
func _world_signature() -> String:
	var config: GenConfig = load(CONFIG_PATH)
	if config == null:
		return ""
	return "%d:%d" % [config.gen_version, config.compute_hash()]


func _save_inventory(cfg: ConfigFile) -> void:
	for i in range(GlobalInventory.SIZE):
		_save_slot(cfg, "slot_%d" % i, GlobalInventory.slots.at(i))
	cfg.set_value("inventory", "active_line", GlobalInventory.active_line)


func _save_slot(cfg: ConfigFile, key: String, slot: GlobalInventory.Slot) -> void:
	cfg.set_value("inventory", key, slot.item.resource_path if slot.item else "")


func _load_inventory(cfg: ConfigFile) -> void:
	_suspend_autosave = true
	GlobalInventory.reset()
	# Pre-rework saves stored bag_*/spell_* keys; those simply read as empty.
	for i in range(GlobalInventory.SIZE):
		_load_slot(cfg, "slot_%d" % i, GlobalInventory.slots.at(i))
	GlobalInventory.set_line(cfg.get_value("inventory", "active_line", 0))
	_suspend_autosave = false


func _load_slot(cfg: ConfigFile, key: String, slot: GlobalInventory.Slot) -> void:
	var path: String = cfg.get_value("inventory", key, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	slot.set_item(load(path))
