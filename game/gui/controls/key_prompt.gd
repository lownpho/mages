@tool
extends TextureRect
class_name KeyPrompt

## One input prompt from the gui/keys.png atlas, picked by name in the inspector — the leaf
## the controls page is built out of. @tool so a page of prompts reads as itself in the
## editor and a name that no longer exists shows up there as an empty cell.
##
## The texture is derived, never stored: the scene keeps the name and nothing else, so
## re-cutting the atlas moves every prompt in the game at once.

@export var icon: StringName = &"":
	set(value):
		icon = value
		texture = KeyIcons.texture(icon) if icon != &"" else null

func _init() -> void:
	# The art is 1:1 and must never be scaled, so the cell is the icon; centring it is all
	# the row alignment a prompt needs.
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _validate_property(property: Dictionary) -> void:
	# The atlas's own names, as a dropdown: picking a prompt is a menu, not a memory test.
	if property.name == "icon":
		var names := PackedStringArray()
		for key in KeyIcons.REGIONS:
			names.append(String(key))
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(names)
	elif property.name == "texture":
		property.usage &= ~PROPERTY_USAGE_STORAGE
