extends Node

## Minimal run persistence: the title screen picks a world seed here, every scene
## reads it back, and it survives between launches so "Continue" can resume the same
## world. A world is a pure function of its seed (see worldgen), so the seed alone
## restores the map; player position and inventory are saved alongside it so Continue
## resumes where the player left off, not just the map they were in.

const SAVE_PATH := "user://save.cfg"

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

var _tracked_player: Node2D = null
var _save_timer: Timer
var _suspend_autosave := false


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.wait_time = POSITION_SAVE_INTERVAL
	_save_timer.timeout.connect(persist)
	add_child(_save_timer)
	GlobalEvent.slot_updated.connect(func(_slot: GlobalInventory.Slot) -> void:
		if not _suspend_autosave:
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
	has_pending_position = true
	_load_inventory(cfg)
	return true


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
	if is_instance_valid(_tracked_player):
		cfg.set_value("player", "position", _tracked_player.global_position)
	_save_inventory(cfg)
	cfg.save(SAVE_PATH)


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
