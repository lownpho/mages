class_name ContentError
extends RefCounted
## One problem the content load pass found, at a file and, when the text is available, a line.

var file := ""
## 1-based; 0 when no line applies or the file has no text to read (an export).
var line := 0
var message := ""


func _init(p_file: String, p_line: int, p_message: String) -> void:
	file = p_file
	line = p_line
	message = p_message


func _to_string() -> String:
	if line > 0:
		return "%s:%d: %s" % [file, line, message]
	return "%s: %s" % [file, message]
