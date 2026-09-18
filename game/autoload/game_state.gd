extends Node

## Run persistence: the title screen picks a world seed here, every scene reads it back, and the
## Run survives between launches so "Continue" can resume the same World. The World is a pure
## function of its seed within one version, so the save holds only what play changed: the seed,
## play time, the player's position and health, the inventory, the Map's records, the Run's defeats
## and the Objects' state. Everything generated is rebuilt from the seed on Continue, and every
## other bit of player or runtime state (cooldowns, buffs, a hurt enemy, AI and loot rolls) starts
## afresh. Death deletes the Run; the Bestiary and Grimoire keep their own files.

const SAVE_PATH := "user://save.cfg"

## Written into every export by addons/app_version: the application version a save is stamped with.
## A save from any other version reads as "nothing to continue" rather than being migrated, since its
## seed would generate a different World. Runs from the editor have no such file and share "dev", so
## development saves of an older shape load as best they can.
const APP_VERSION_FILE := "res://app_version.txt"
const DEV_VERSION := "dev"

## How often to resave the player's position while playing. Inventory changes persist
## immediately (they're user-driven and rare); position drifts every frame, so it's
## only snapshotted periodically instead of on every movement.
const POSITION_SAVE_INTERVAL := 4.0

## Where the Run is written. Tests point it elsewhere so they never touch a player's save.
var save_path := SAVE_PATH

## The seed for this session's world. 0 = nothing chosen yet (editor-launched a game
## scene directly), so scenes fall back to their own default.
var active_seed := 0

## True for the first world entry of a brand-new run, so world.gd can drop starter gear
## next to the player exactly once. Runtime-only (never saved); Continue leaves it false.
var fresh_start := false

## Position and health loaded from a Continue'd save, for the World scene to place the player with
## instead of the spawn and full health. Only meaningful when set by continue_game(); health 0 means
## none was saved.
var pending_player_position: Vector2 = Vector2.ZERO
var has_pending_position := false
var pending_player_health := 0

## True while a scene that is NOT a run is live — the tutorial. Everything that would touch the
## player's saved run checks it: the save file here, and the bestiary in its own autoload.
## The tutorial is reachable from the title with a real run already saved, and it can be left
## three ways (its exit door, death, the HUD's quit button), so "writes nothing" has to hold
## at the writers rather than at each way out.
var sandbox := false

## Debug seed and spatial-tuning edits make the live World differ from the Run identity that would
## be written to disk. Keep that fact at the save owner rather than on a particular debug panel so
## later autosaves cannot accidentally re-enable the Run. Normal movement, fly, teleports, item
## changes and spawned entities never touch this flag.
var run_save_eligible := true
var run_save_disabled_reason := ""

var _tracked_player: Node2D = null
var _tracked_encounters: EncounterSpawner = null
var _tracked_objects: ObjectSpawner = null
var _save_timer: Timer
var _suspend_autosave := false
## A Continue'd Run's defeats (with its play time) and Object states, held from continue_game()
## until the World scene rebuilding the saved seed takes them. Null when no Continue is pending.
var _pending_defeats: RunDefeats = null
var _pending_object_states: Dictionary = {}
## The World New was started in, already planned by the title backdrop, until world.gd takes it.
var _planned_world: WorldGraph = null
var _cli_seed_taken := false


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
	# A Sign's reveal is user-driven and rare (like inventory edits), so persist immediately rather
	# than waiting for the periodic tick — same tracked-player gate to avoid a position-less write.
	GlobalMap.room_revealed.connect(func(_room_key: String) -> void:
		if not _suspend_autosave and is_instance_valid(_tracked_player):
			persist())


## The version this build stamps saves with: the export's stamp, or DEV_VERSION outside an export.
static func app_version() -> String:
	if not FileAccess.file_exists(APP_VERSION_FILE):
		return DEV_VERSION
	var stamped := FileAccess.get_file_as_string(APP_VERSION_FILE).strip_edges()
	return stamped if not stamped.is_empty() else DEV_VERSION


## Whether there is a Run this version can Continue. A save from another version is invisible.
func has_save() -> bool:
	return _load_save() != null


## Start a fresh Run in memory: in an already planned World when given one (the title backdrop's),
## else at world_seed, else at a rolled seed. The save is written once the World scene loads
## (world.gd calls persist()); fresh_start flags that first entry so the player is handed a
## starter hand.
func new_game(world_seed := 0, planned: WorldGraph = null) -> void:
	run_save_eligible = true
	run_save_disabled_reason = ""
	fresh_start = true
	_clear_pending()
	if planned != null:
		world_seed = planned.plan.world_seed
		_planned_world = planned
	active_seed = world_seed if world_seed != 0 else maxi(randi(), 1)  # keep 0 reserved for "unset"
	# Fresh run: nothing carries over. The bestiary (its own autoload) is intentionally
	# left alone so kill discoveries persist across runs.
	GlobalMap.reset()
	_suspend_autosave = true
	GlobalInventory.reset()
	_suspend_autosave = false


## Load the saved Run into the session, for the World scene to rebuild. Returns false if there is
## nothing to continue.
func continue_game() -> bool:
	var cfg := _load_save()
	if cfg == null:
		return false
	run_save_eligible = true
	run_save_disabled_reason = ""
	fresh_start = false
	_clear_pending()
	active_seed = int(cfg.get_value("run", "seed", 0))
	# A missing key (a position-less save) must NOT fall back to Vector2.ZERO — that drops the
	# player at the world origin — so only a stored position is pending; otherwise the spawn.
	has_pending_position = cfg.has_section_key("player", "position")
	pending_player_position = cfg.get_value("player", "position", Vector2.ZERO)
	pending_player_health = int(cfg.get_value("player", "health", 0))
	# The Map's records are Room keys and tiles of the same seed's World. GlobalMap stashes them
	# until the World scene builds the Map (Continue runs on the title, before the World exists).
	GlobalMap.restore(cfg.get_value("map", "state", {}))
	_pending_defeats = RunDefeats.new()
	_pending_defeats.play_time = float(cfg.get_value("run", "play_time", 0.0))
	for key in cfg.get_value("defeats", "defeated", []):
		_pending_defeats.defeated[String(key)] = true
	var deaths: Dictionary = cfg.get_value("defeats", "deaths", {})
	for key in deaths:
		_pending_defeats.deaths[String(key)] = float(deaths[key])
	_pending_object_states = cfg.get_value("objects", "states", {})
	_load_inventory(cfg)
	return true


## True from continue_game() until the World scene takes the saved Run's records.
func continuing_run() -> bool:
	return _pending_defeats != null


## The Run's defeats for the World being built: the Continue'd Run's, with its play time, else a
## new Run's empty record. Offline time never counts, as play time resumes where it was saved.
func take_run_defeats() -> RunDefeats:
	var out := _pending_defeats if _pending_defeats != null else RunDefeats.new()
	_pending_defeats = null
	return out


## The Continue'd Run's non-empty Object states, else none.
func take_object_states() -> Dictionary:
	var out := _pending_object_states
	_pending_object_states = {}
	return out


## The already planned World new_game() was given, once; null when the World must plan its own.
func take_planned_world() -> WorldGraph:
	var out := _planned_world
	_planned_world = null
	return out


## A seed given on the command line (`-- seed=123`), once per launch so returning to the title
## doesn't start another Run; 0 when none was given or it was already taken.
func take_cli_seed() -> int:
	if _cli_seed_taken:
		return 0
	_cli_seed_taken = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seed=") and arg.trim_prefix("seed=").is_valid_int():
			return arg.trim_prefix("seed=").to_int()
	return 0


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


## Called by the World scene so every save carries its defeats and Object states.
func track_world(encounters: EncounterSpawner, objects: ObjectSpawner) -> void:
	_tracked_encounters = encounters
	_tracked_objects = objects


## The Map's recall: carry the tracked player to a discovered tile. Fountains are the only clickable
## marks, and MapState marks only entered Rooms, so this can never land somewhere unseen.
func teleport_to(tile: Vector2i) -> void:
	if is_instance_valid(_tracked_player) and is_instance_valid(_tracked_objects):
		_tracked_objects.warp_to(_tracked_player, tile)


## True while a live run is in progress (a player is placed in the world). Loadout
## edits at the title — the Continue restore, new_game's reset — happen outside it.
func in_run() -> bool:
	return is_instance_valid(_tracked_player)


## Wipe the save so there is nothing to Continue. Called on death.
func clear_save() -> void:
	if sandbox:
		return
	active_seed = 0
	_clear_pending()
	_tracked_player = null
	_tracked_encounters = null
	_tracked_objects = null
	GlobalMap.reset()
	_save_timer.stop()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)


## The run ended (the player died): wipe the run — save and inventory — and return to
## the title screen. The bestiary (its own autoload) persists across runs. In a sandbox
## there is no run to end, so clear_save() no-ops and this is only the trip home.
func game_over() -> void:
	clear_save()
	_suspend_autosave = true
	GlobalInventory.reset()
	_suspend_autosave = false
	SceneManager.go_to(load("res://scenes/title.tscn"))


## Irreversible for this Run: once its authored seed or spatial inputs were edited, no later revert
## can prove that every generated/runtime value matches the save identity again.
func disable_run_saving(reason: String) -> void:
	run_save_eligible = false
	if run_save_disabled_reason.is_empty():
		run_save_disabled_reason = reason


func can_save_run() -> bool:
	return not sandbox and run_save_eligible


## Persist the current run so "Continue" can resume it. Called on world entry, on every inventory
## or Pin change, periodically while playing and on Quit. Every write passes through here, so a
## sandbox or a debug-edited World writes nothing.
func persist() -> void:
	if not can_save_run():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("run", "version", app_version())
	cfg.set_value("run", "seed", active_seed)
	cfg.set_value("map", "state", GlobalMap.to_dict())
	if is_instance_valid(_tracked_player):
		cfg.set_value("player", "position", _tracked_player.global_position)
		cfg.set_value("player", "health", int(_tracked_player.get("health")))
	if is_instance_valid(_tracked_encounters):
		var defeats := _tracked_encounters.defeats
		cfg.set_value("run", "play_time", defeats.play_time)
		var defeated: Array[String] = []
		defeated.assign(defeats.defeated.keys())
		defeated.sort()
		cfg.set_value("defeats", "defeated", defeated)
		cfg.set_value("defeats", "deaths", defeats.deaths.duplicate())
	if is_instance_valid(_tracked_objects):
		cfg.set_value("objects", "states", _tracked_objects.saved_states())
	_save_inventory(cfg)
	cfg.save(save_path)


## The save file when this version can Continue it, else null.
func _load_save() -> ConfigFile:
	if not FileAccess.file_exists(save_path):
		return null
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return null
	if String(cfg.get_value("run", "version", "")) != app_version() or int(cfg.get_value("run", "seed", 0)) == 0:
		return null
	return cfg


func _clear_pending() -> void:
	has_pending_position = false
	pending_player_health = 0
	_pending_defeats = null
	_pending_object_states = {}
	_planned_world = null


func _save_inventory(cfg: ConfigFile) -> void:
	for i in range(GlobalInventory.SPELL_SLOTS):
		_save_slot(cfg, "spell_%d" % i, GlobalInventory.spell_slots.at(i))
	for i in range(GlobalInventory.BAG_SIZE):
		_save_slot(cfg, "bag_%d" % i, GlobalInventory.bag_slots.at(i))


func _save_slot(cfg: ConfigFile, key: String, slot: GlobalInventory.Slot) -> void:
	cfg.set_value("inventory", key, slot.item.resource_path if slot.item else "")


func _load_inventory(cfg: ConfigFile) -> void:
	_suspend_autosave = true
	GlobalInventory.reset()
	for i in range(GlobalInventory.SPELL_SLOTS):
		_load_slot(cfg, "spell_%d" % i, GlobalInventory.spell_slots.at(i))
	for i in range(GlobalInventory.BAG_SIZE):
		_load_slot(cfg, "bag_%d" % i, GlobalInventory.bag_slots.at(i))
	_suspend_autosave = false


func _load_slot(cfg: ConfigFile, key: String, slot: GlobalInventory.Slot) -> void:
	var path: String = cfg.get_value("inventory", key, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	slot.set_item(load(path))
