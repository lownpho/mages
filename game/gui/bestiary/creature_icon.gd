class_name CreatureIcon
extends TextureRect

## A creature thumbnail for the bestiary: once the enemy is unlocked it plays that enemy's
## idle loop (the exact SpriteFrames off its scene), so the book shows living creatures rather
## than frozen frames. While locked it shows a single idle frame flattened to a gray silhouette
## — the "not discovered yet" signal, no text needed. Shared by the grid cards and the boss
## emblem; author it as the Icon node's script and drive it with show_creature().

const IDLE := &"idle"
const _FLATTEN := preload("res://gui/flatten.gdshader")
# The bag-slot gray: silhouettes must contrast with the panel, whose frame texture is the
# palette dark. The flatten shader forces a single raw palette color, never a modulate blend.
const _SILHOUETTE_COLOR := Palette.GREY

static var _silhouette_material: ShaderMaterial

var _frames: Array[Texture2D] = []
var _fps: float = 1.0
var _t: float = 0.0
var _i: int = 0

func _ready() -> void:
	set_process(false)

## Bind to an enemy id: animate its idle loop when `unlocked`, else show its silhouette.
## &"" clears the icon (blank filler cell).
func show_creature(id: StringName, unlocked: bool) -> void:
	_frames.clear()
	set_process(false)
	material = null
	if id == &"":
		texture = null
		return
	var data := GlobalBestiary.load_data(id)
	if not unlocked:
		texture = data.icon
		material = _get_silhouette()
		return
	var sf := GlobalBestiary.idle_frames(id)
	if sf != null and sf.has_animation(IDLE) and sf.get_frame_count(IDLE) > 0:
		_fps = maxf(0.1, sf.get_animation_speed(IDLE))
		for f in sf.get_frame_count(IDLE):
			_frames.append(sf.get_frame_texture(IDLE, f))
		_i = 0
		_t = 0.0
		texture = _frames[0]
		set_process(_frames.size() > 1 and is_visible_in_tree())
	else:
		texture = data.icon  # no idle frames authored → the static idle icon

func _process(delta: float) -> void:
	_t += delta
	var step := 1.0 / _fps
	while _t >= step:
		_t -= step
		_i = (_i + 1) % _frames.size()
	texture = _frames[_i]

# Don't burn frames animating while the book is closed; resume on reopen.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(_frames.size() > 1 and is_visible_in_tree())

static func _get_silhouette() -> ShaderMaterial:
	if not _silhouette_material:
		_silhouette_material = ShaderMaterial.new()
		_silhouette_material.shader = _FLATTEN
		_silhouette_material.set_shader_parameter("flat_color", _SILHOUETTE_COLOR)
	return _silhouette_material
