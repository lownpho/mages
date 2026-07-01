extends Node2D
## Free-fly debug camera (scenes/debug_world.tscn). Sits in the "player" group so ChunkStreamer
## streams the world around it; ignores physics, so fly anywhere. Yellow box = the player's real
## 320×180 view drawn at world size (shrinks as you zoom out). HUD shows tile pos vs world bounds.

const PLAYER_VIEW := Vector2(320, 180)   # base viewport = the real play view, in world px
const PAN := 220.0                       # on-screen px/sec (world speed scales with zoom)
const ZOOM_STEP := 1.15

@onready var _cam: Camera2D = $Camera2D
@onready var _label: Label = $HUD/Label


func _ready() -> void:
	add_to_group("player")
	_cam.zoom = Vector2(0.3, 0.3)
	# The hull is now the union of biome cells (no fixed region grid) — the rich minimap /
	# bounds overlay is Group J's job. This cam just flies and shows the tile position.


func _process(dt: float) -> void:
	var v := Vector2(
		float(_key(KEY_D, KEY_RIGHT)) - float(_key(KEY_A, KEY_LEFT)),
		float(_key(KEY_S, KEY_DOWN)) - float(_key(KEY_W, KEY_UP)))
	if v != Vector2.ZERO:
		global_position += v.normalized() * PAN * dt / _cam.zoom.x
	var t := (global_position / GameConstants.PX_PER_TILE).round()
	_label.text = "WASD/arrows fly · wheel zoom\npos %d,%d   ×%.2f" % [
		int(t.x), int(t.y), _cam.zoom.x]
	queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam.zoom = (_cam.zoom * ZOOM_STEP).clampf(0.04, 4.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam.zoom = (_cam.zoom / ZOOM_STEP).clampf(0.04, 4.0)


func _draw() -> void:
	draw_rect(Rect2(-PLAYER_VIEW * 0.5, PLAYER_VIEW), Color(1, 0.92, 0.2), false, 2.0 / _cam.zoom.x)


func _key(a: int, b: int) -> bool:
	return Input.is_key_pressed(a) or Input.is_key_pressed(b)
