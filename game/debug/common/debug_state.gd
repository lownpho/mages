class_name DebugState
## Shared persistence for the debug tools (the World debug layer, console). State lives in
## user://debug_state.cfg so an F5 restart resumes where the last session left off.
extends RefCounted

const PATH := "user://debug_state.cfg"

## The pixel font debug overlays label themselves with, at its native size.
const UI_FONT := preload("res://gui/m3x6.ttf")
const UI_FONT_SIZE := 8

static var _cfg: ConfigFile = null


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
