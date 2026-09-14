@tool
extends EditorExportPlugin
## Writes the application version into every export as GameState.APP_VERSION_FILE, so a save made by
## another build hides Continue. The version is the project's git description; an export with
## uncommitted changes, or made without git, also carries its export time, so it never claims to be
## a build it isn't.

## Keep in step with GameState.APP_VERSION_FILE.
const FILE := "res://app_version.txt"


func _get_name() -> String:
	return "AppVersion"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var version := stamp()
	add_file(FILE, version.to_utf8_buffer(), false)
	print("App version: ", version)


static func stamp() -> String:
	var output: Array = []
	var described := ""
	if OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "describe", "--always", "--dirty"], output) == 0 \
			and not output.is_empty():
		described = String(output[0]).strip_edges()
	var time := Time.get_datetime_string_from_system(true).replace(":", "")
	if described.is_empty():
		return time
	return "%s-%s" % [described, time] if described.ends_with("-dirty") else described
