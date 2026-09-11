extends PanelContainer

## One grimoire card: a spell's 8x8 icon, or — until that spell has been picked up — the same icon
## flattened to a gray silhouette, the bestiary's "not discovered yet" signal. No text either way.
## The learned state is handed in rather than looked up.
##
## The cell is a FIXED size and centres the icon, so the grid never reflows around the art.

const _FLATTEN := preload("res://gui/flatten.gdshader")
# The bestiary's silhouette gray: it has to contrast with the panel's dark frame, and the flatten
# shader forces a single raw palette color, never a modulate blend.
const _SILHOUETTE_COLOR := Palette.GREY

static var _silhouette_material: ShaderMaterial

## The entry this card shows (GlobalGrimoire's entry id).
var id: StringName = &""

func show_entry(p_id: StringName, learned: bool) -> void:
	id = p_id
	var spell := GlobalGrimoire.load_spell(id)
	%Icon.texture = spell.icon if spell else null
	%Icon.material = null if learned else _get_silhouette()

static func _get_silhouette() -> ShaderMaterial:
	if not _silhouette_material:
		_silhouette_material = ShaderMaterial.new()
		_silhouette_material.shader = _FLATTEN
		_silhouette_material.set_shader_parameter("flat_color", _SILHOUETTE_COLOR)
	return _silhouette_material
