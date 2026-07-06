extends PanelContainer

## One bestiary card: the enemy's idle-frame icon plus its kill count. Locked entries
## (never killed) show the icon flattened to the palette dark — a silhouette — and no
## count; the silhouette itself is the "not discovered yet" signal, no text needed.

const _FLATTEN_SHADER = preload("res://gui/flatten.gdshader")
# The bag-slot gray: silhouettes must contrast with the panel, whose frame texture is
# the palette dark. The flatten shader keeps the output a single raw palette color,
# never a modulate blend.
const _SILHOUETTE_COLOR = Palette.GREY

static var _silhouette_material: ShaderMaterial

var enemy_id: StringName = &""

func _ready() -> void:
	GlobalEvent.bestiary_updated.connect(_on_bestiary_updated)

## Bind the card to an enemy type, or to &"" for a blank filler cell (frame only) so
## the last page keeps a full, stable grid.
func show_entry(id: StringName) -> void:
	enemy_id = id
	if id == &"":
		%Icon.texture = null
		%Count.text = ""
		return
	%Icon.texture = GlobalBestiary.load_data(id).icon
	_refresh()

func _refresh() -> void:
	if GlobalBestiary.is_unlocked(enemy_id):
		%Icon.material = null
		%Count.text = str(GlobalBestiary.kill_count(enemy_id))
	else:
		%Icon.material = _get_silhouette()
		%Count.text = ""

func _on_bestiary_updated(id: StringName, _kills: int) -> void:
	if id == enemy_id:
		_refresh()

static func _get_silhouette() -> ShaderMaterial:
	if not _silhouette_material:
		_silhouette_material = ShaderMaterial.new()
		_silhouette_material.shader = _FLATTEN_SHADER
		_silhouette_material.set_shader_parameter("flat_color", _SILHOUETTE_COLOR)
	return _silhouette_material
