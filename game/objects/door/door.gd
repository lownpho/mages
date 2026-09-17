@tool
class_name Door
extends Area2D

## A walk-in door. A hand-placed one points at a `target_scene` and switches scenes (the tutorial's
## exit); a Professor's portal is set up from generated data and asks its ObjectSpawner to move the
## player to a landing tile in its destination Room. Both are this one scene: only the data differs.

## A portal was walked into. Its ObjectSpawner moves `body` to `landing`.
signal warp_entered(body: Node2D, destination_room: String, landing: Vector2i)

## Art variants packed in doors.png, one 16×16 frame each (left → right). PORTAL has no frame
## drawn yet and renders blank.
enum Style { WOOD, HEDGE, CAVE, PORTAL, MUSHROOM }

const _FRAME_W := 16

@export var style := Style.WOOD: # Runs on assignment so the editor preview tracks the choice.
	set(value):
		style = value
		_apply_style()

## The scene to switch to when the player steps on this door. Leave null to place
## a door before its destination exists; it just warns and stays put when used.
@export var target_scene: PackedScene

## A portal ignores `target_scene`: it leads to the landing tile in its destination Room, and
## warp_entered asks for the move. Vector2i.MAX = not one.
var destination_room := ""
var landing := Vector2i.MAX

# Guards against firing twice while the deferred scene change is pending.
var _used := false
# A door only fires while nothing was standing in it as of the last physics step: a streamed-in
# door can materialise right under the player (including one in the room a warp just dropped them
# in), which must not read as walking through it. `_physics_process` runs BEFORE the step
# whose body_entered signals arrive, so `_armed` always describes the frame the body came from.
# Overlap data is empty until the node has been through a step, hence the settle frames.
const _SETTLE_FRAMES := 2

var _armed := false
var _settle := _SETTLE_FRAMES

# Using any door locks EVERY door for a moment: a warp can land the player next to a door the
# destination room happens to hold, and a fast enough body could trip it before the arrival
# settles and be flung straight on again.
const _COOLDOWN_MS := 1000
static var _last_use_ms := -_COOLDOWN_MS


func _ready() -> void:
	_apply_style()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	body_entered.connect(_on_body_entered)


## Configure a portal from its generated data (Professor): its destination Room key, landing tile
## and the destination Biome's door art. A door keeps no Object state.
func setup(data: Dictionary) -> void:
	style = data.art            # setter re-applies the art once in-tree
	destination_room = data.destination_room
	landing = data.landing


func _apply_style() -> void:
	if not is_node_ready():
		return
	$Sprite2D.region_rect.position.x = style * _FRAME_W


func _physics_process(_dt: float) -> void:
	if _settle > 0:
		_settle -= 1
		return
	_armed = get_overlapping_bodies().is_empty()


func _on_body_entered(body: Node2D) -> void:
	if not _armed:
		return
	if Time.get_ticks_msec() - _last_use_ms < _COOLDOWN_MS:
		return
	if landing != Vector2i.MAX:
		_armed = false
		_last_use_ms = Time.get_ticks_msec()
		warp_entered.emit(body, destination_room, landing)
		return
	if _used:
		return
	if not target_scene:
		push_warning("Door at %s has no target_scene" % global_position)
		return
	_used = true
	_last_use_ms = Time.get_ticks_msec()
	SceneManager.go_to(target_scene)
