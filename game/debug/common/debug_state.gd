class_name DebugState
## Shared persistence + CLI deep-links for the debug tools (worldgen debug, room lab,
## combat lab, console). State lives in user://debug_state.cfg so an F5 restart resumes
## where the last session left off; CLI user args (after "--") override the stored state
## so an exact tool state is reproducible from a shell command, e.g.:
##   godot --path game res://debug/worldgen/worldgen_debug.tscn -- seed=123 view=4 pos=40,20
extends RefCounted

const PATH := "user://debug_state.cfg"

static var _cfg: ConfigFile = null
static var _cli: Dictionary = {}
static var _cli_parsed := false


static func _file() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)   # missing file is fine — starts empty
	return _cfg


static func get_value(section: String, key: String, default: Variant = null) -> Variant:
	# has_section_key guard: ConfigFile.get_value error-spams when the key is missing
	# and the default is null.
	if not _file().has_section_key(section, key):
		return default
	return _file().get_value(section, key, default)


static func set_value(section: String, key: String, value: Variant) -> void:
	_file().set_value(section, key, value)
	_file().save(PATH)


static func erase(section: String, key: String) -> void:
	var f := _file()
	if f.has_section_key(section, key):
		f.erase_section_key(section, key)
		f.save(PATH)


static func keys(section: String) -> PackedStringArray:
	var f := _file()
	if not f.has_section(section):
		return PackedStringArray()
	return f.get_section_keys(section)


## CLI user args (everything after "--"), parsed as key=value pairs; "--key=value" also
## accepted. Returns "" when absent.
static func cli_arg(key: String) -> String:
	if not _cli_parsed:
		_cli_parsed = true
		for a in OS.get_cmdline_user_args():
			var arg: String = a.trim_prefix("--")
			var eq := arg.find("=")
			if eq > 0:
				_cli[arg.substr(0, eq)] = arg.substr(eq + 1)
	return _cli.get(key, "")


static func cli_int(key: String, default: int) -> int:
	var v := cli_arg(key)
	return v.to_int() if v != "" else default


## "x,y" CLI arg as a Vector2i, or `default` when absent/malformed.
static func cli_vec2i(key: String, default: Vector2i) -> Vector2i:
	var v := cli_arg(key)
	var parts := v.split(",")
	if parts.size() != 2:
		return default
	return Vector2i(parts[0].to_int(), parts[1].to_int())
