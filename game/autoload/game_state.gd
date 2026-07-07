extends Node

## Minimal run persistence: the title screen picks a world seed here, every scene
## reads it back, and it survives between launches so "Continue" can resume the same
## world. A world is a pure function of its seed (see worldgen), so the seed alone
## restores the map; player position and inventory are saved alongside it so Continue
## resumes where the player left off, not just the map they were in.

const SAVE_PATH := "user://save.cfg"

## The world is a pure function of (seed, gen_version, CONFIG_HASH); the same seed lays out
## a different map once the generation code or config changes. We stamp the save with the
## current world signature so Continue can tell whether a stored player position still lands
## where it did — a mismatch means the layout moved under it, so the position is discarded
## and the run respawns at the deterministic spawn instead of inside what is now a wall.
const CONFIG_PATH := "res://world_content/gen_config.tres"

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


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.wait_time = POSITION_SAVE_INTERVAL
	_save_timer.timeout.connect(persist)
	add_child(_save_timer)
	# Autosave on inventory edits, but only once a player is being tracked: persist() rebuilds
	# the save from scratch and would otherwise write a position-less save (it only stores the
	# position when a player is tracked), which Continue then reads back as (0,0). Inventory
	# changes during scene transitions — before world.gd calls track_player — are exactly that
	# window, so gate on it.
	GlobalEvent.slot_updated.connect(func(_slot: GlobalInventory.Slot) -> void:
		if not _suspend_autosave and is_instance_valid(_tracked_player):
			persist())


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


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
	_suspend_autosave = true
	GlobalInventory.reset()
	_suspend_autosave = false


## Load the saved seed, position, and inventory into the session. Returns false if
## there is nothing to continue.
func continue_game() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
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
	notable_kills = cfg.get_value("world", "notable_kills", {})
	_load_inventory(cfg)
	return true


## Record a defeated rare/boss enemy and persist immediately (rare enough that this is
## cheap, and important enough not to lose to a crash between now and the next autosave).
func record_notable_kill(entity_id: int) -> void:
	notable_kills[entity_id] = true
	persist()


## Called once by world.gd after placing the (possibly restored) player, so the
## periodic position autosave and immediate inventory autosave have a target.
func track_player(player: Node2D) -> void:
	_tracked_player = player
	_save_timer.start()


## Wipe the save so there is nothing to Continue. Called on death.
func clear_save() -> void:
	active_seed = 0
	has_pending_position = false
	_tracked_player = null
	_save_timer.stop()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


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
	cfg.set_value("world", "seed", active_seed)
	cfg.set_value("world", "signature", _world_signature())
	cfg.set_value("world", "notable_kills", notable_kills)
	if is_instance_valid(_tracked_player):
		cfg.set_value("player", "position", _tracked_player.global_position)
	_save_inventory(cfg)
	cfg.save(SAVE_PATH)


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
	_save_slot(cfg, "weapon", GlobalInventory.weapon_slot)
	_save_slot(cfg, "hat", GlobalInventory.hat_slot)
	_save_slot(cfg, "robe", GlobalInventory.robe_slot)
	for i in range(GlobalInventory.bag_slots.slots.size()):
		_save_slot(cfg, "bag_%d" % i, GlobalInventory.bag_slots.at(i))
	for i in range(GlobalInventory.spell_slots.slots.size()):
		_save_slot(cfg, "spell_%d" % i, GlobalInventory.spell_slots.at(i))


func _save_slot(cfg: ConfigFile, key: String, slot: GlobalInventory.Slot) -> void:
	cfg.set_value("inventory", key, slot.item.resource_path if slot.item else "")


func _load_inventory(cfg: ConfigFile) -> void:
	_suspend_autosave = true
	GlobalInventory.reset()
	_load_slot(cfg, "weapon", GlobalInventory.weapon_slot)
	_load_slot(cfg, "hat", GlobalInventory.hat_slot)
	_load_slot(cfg, "robe", GlobalInventory.robe_slot)
	for i in range(GlobalInventory.bag_slots.slots.size()):
		_load_slot(cfg, "bag_%d" % i, GlobalInventory.bag_slots.at(i))
	for i in range(GlobalInventory.spell_slots.slots.size()):
		_load_slot(cfg, "spell_%d" % i, GlobalInventory.spell_slots.at(i))
	_suspend_autosave = false


func _load_slot(cfg: ConfigFile, key: String, slot: GlobalInventory.Slot) -> void:
	var path: String = cfg.get_value("inventory", key, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	slot.set_item(load(path))
