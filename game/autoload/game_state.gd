extends Node

## Minimal run persistence: the title screen picks a world seed here, every scene
## reads it back, and it survives between launches so "Continue" can resume the same
## world. A world is a pure function of its seed (see worldgen), so the seed *is* the save.

const SAVE_PATH := "user://save.cfg"

## The seed for this session's world. 0 = nothing chosen yet (editor-launched a game
## scene directly), so scenes fall back to their own default.
var active_seed := 0


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Roll a fresh world and persist it so it becomes the thing "Continue" resumes.
func new_game() -> void:
	active_seed = randi()
	if active_seed == 0:
		active_seed = 1  # keep 0 reserved for "unset"
	# Fresh run: nothing carries over. The bestiary (its own autoload) is intentionally
	# left alone so kill discoveries persist across runs.
	GlobalInventory.reset()
	_write()


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


func _write() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("world", "seed", active_seed)
	cfg.save(SAVE_PATH)
