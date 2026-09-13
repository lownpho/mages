class_name TresIndex
extends RefCounted
## Where things are written in one text resource file, so the content load pass can point at the line
## behind a problem. The engine does the loading; this only reads lines.


## One [resource] or [sub_resource] section.
class Section:
	## The sub-resource id; "" for [resource].
	var id := ""
	var line := 0
	## The ext id of the section's script.
	var script_id := ""
	## Property -> line.
	var properties: Dictionary[String, int] = {}
	## Property -> one {line, key} per dictionary entry written on its own line. The key is the path
	## of an ExtResource key, otherwise the key as written.
	var entries: Dictionary[String, Array] = {}


static var _property := RegEx.create_from_string("^([A-Za-z_][A-Za-z0-9_/]*) = ")
static var _attribute := RegEx.create_from_string("(\\w+)=\"([^\"]*)\"")
static var _ext_call := RegEx.create_from_string("^ExtResource\\(\"([^\"]*)\"\\)$")
static var _script_call := RegEx.create_from_string("= ExtResource\\(\"([^\"]*)\"\\)")
static var _entry := RegEx.create_from_string("^\\s*((?:Ext|Sub)Resource\\(\"[^\"]*\"\\)|-?[0-9.]+|&?\"(?:[^\"\\\\]|\\\\.)*\")\\s*:")

var path := ""
## Ext id -> path.
var ext_paths: Dictionary[String, String] = {}
var sections: Array[Section] = []


## null when path has no text to read, as in an export, where resources are remapped binaries.
static func read(file: String) -> TresIndex:
	if not FileAccess.file_exists(file):
		return null
	var index := TresIndex.new()
	index.path = file
	index._parse(FileAccess.get_file_as_string(file))
	return index


## The line of a property in a section ("" for [resource]); with a key, the line of that dictionary
## entry. Falls back to the property's line, then the section's, then 0.
func line_of(section_id: String, property: String, key: Variant = null) -> int:
	var section := _section(section_id)
	if section == null:
		return 0
	if key != null:
		var wanted := (key as Resource).resource_path if key is Resource else str(key)
		for entry: Dictionary in section.entries.get(property, []):
			if entry.key == wanted:
				return entry.line
	return section.properties.get(property, section.line)


## A dictionary property's entries, one {line, key} each, as written.
func entries(section_id: String, property: String) -> Array:
	var section := _section(section_id)
	return [] if section == null else section.entries.get(property, [])


## Properties a section sets that its script doesn't declare, as {line, name, script}. A load drops
## those without a word.
func unknown_properties() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for section in sections:
		var script_path: String = ext_paths.get(section.script_id, "")
		if script_path == "" or not ResourceLoader.exists(script_path):
			continue
		var script := load(script_path) as Script
		if script == null:
			continue
		var known: Dictionary[String, bool] = {"script": true}
		for property in script.get_script_property_list():
			known[property.name] = true
		for property in ClassDB.class_get_property_list(script.get_instance_base_type()):
			known[property.name] = true
		for property_name in section.properties:
			if not known.has(property_name) and not property_name.begins_with("metadata/"):
				out.append({"line": section.properties[property_name], "name": property_name, "script": script_path})
	return out


func _section(section_id: String) -> Section:
	for section in sections:
		if section.id == section_id:
			return section
	return null


func _parse(text: String) -> void:
	var depth := 0
	var in_string := false
	var escaped := false
	var property := ""
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i].trim_suffix("\r")
		if depth == 0 and not in_string:
			if line.begins_with("["):
				_header(line, i + 1)
				property = ""
				continue
			var found := _property.search(line)
			if found != null and not sections.is_empty():
				property = found.get_string(1)
				sections[-1].properties[property] = i + 1
				var script := _script_call.search(line)
				if property == "script" and script != null:
					sections[-1].script_id = script.get_string(1)
		elif not in_string and property != "" and not sections.is_empty():
			var key := _entry.search(line)
			if key != null:
				var section := sections[-1]
				if not section.entries.has(property):
					section.entries[property] = []
				section.entries[property].append({"line": i + 1, "key": _key(key.get_string(1))})
		for c in line:
			if in_string:
				if escaped:
					escaped = false
				elif c == "\\":
					escaped = true
				elif c == "\"":
					in_string = false
			elif c == "\"":
				in_string = true
			elif c in "[({":
				depth += 1
			elif c in "])}":
				depth -= 1


func _header(line: String, number: int) -> void:
	var tag := line.substr(1).get_slice(" ", 0).trim_suffix("]")
	var attributes: Dictionary[String, String] = {}
	for found in _attribute.search_all(line):
		attributes[found.get_string(1)] = found.get_string(2)
	match tag:
		"ext_resource":
			ext_paths[attributes.get("id", "")] = attributes.get("path", "")
		"sub_resource", "resource":
			var section := Section.new()
			section.id = attributes.get("id", "")
			section.line = number
			sections.append(section)


func _key(written: String) -> String:
	var ext := _ext_call.search(written)
	if ext != null and ext_paths.has(ext.get_string(1)):
		return ext_paths[ext.get_string(1)]
	return written
