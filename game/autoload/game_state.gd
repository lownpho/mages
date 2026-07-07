extends Node

## Minimal run persistence: the title screen picks a world seed here, every scene
## reads it back, and it survives between launches so "Continue" can resume the same
## world. A world is a pure function of its seed (see worldgen), so the seed *is* the save.

const SAVE_PATH := "user://save.cfg"

## The seed for this session's world. 0 = nothing chosen yet (editor-launched a game
## scene directly), so scenes fall back to their own default.
var active_seed := 0

## True for the first world entry of a brand-new run, so world.gd can drop starter gear
## next to the player exactly once. Runtime-only (never saved); Continue leaves it false.
var fresh_start := false


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
	# Fresh run: nothing carries over. The bestiary (its own autoload) is intentionally
	# left alone so kill discoveries persist across runs.
	GlobalInventory.reset()


## Load the saved seed into the session. Returns false if there is nothing to continue.
func continue_game() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	active_seed = int(cfg.get_value("world", "seed", 0))
	return active_seed != 0


## Wipe the save so there is nothing to Continue. Called on death.
func clear_save() -> void:
	active_seed = 0
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## The run ended (the player died): wipe the run — save and inventory — and return to
## the title screen. The bestiary (its own autoload) persists across runs.
func game_over() -> void:
	clear_save()
	GlobalInventory.reset()
	SceneManager.go_to(load("res://scenes/title.tscn"))


## Persist the current run so "Continue" can resume it. Called on world entry (world.gd),
## not on new_game() — a run isn't saved until the player reaches the world.
func persist() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("world", "seed", active_seed)
	cfg.save(SAVE_PATH)
