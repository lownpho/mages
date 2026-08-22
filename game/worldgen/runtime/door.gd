@tool
class_name Door
extends Area2D

## A generic scene-transition trigger. Drop one anywhere — by hand in a scene or
## spawned by the world generator — point it at a `target_scene`, pick a `style`
## for the art, and walking the player onto it switches scenes.
##
## Every door in the game (dungeon entrance, dungeon floor stairs, tutorial exit)
## is this one scene: only the exported data differs.

## Art variants packed in doors.png, one 16×16 frame each (left → right). PORTAL has no frame
## drawn yet and renders blank. STAIRS_UP/STAIRS_DOWN are one biome's two vertical ends, so the
## pair only means anything where something picks between them — a flat biome just uses one.
enum Style { WOOD, HEDGE, CAVE, PORTAL, STAIRS_UP, MUSHROOM, STAIRS_DOWN }

const _FRAME_W := 16

@export var style := Style.WOOD: # Runs on assignment so the editor preview tracks the choice.
	set(value):
		style = value
		_apply_style()

## The scene to switch to when the player steps on this door. Leave null to place
## a door before its destination exists; it just warns and stays put when used.
@export var target_scene: PackedScene

## Two-way warp doors ignore `target_scene` and name the world slot of their twin's room
## instead — the world moves the player beside that door and back again. Vector2i.MAX = not one.
@export var target_slot := Vector2i.MAX

# Guards against firing twice while the deferred scene change is pending.
var _used := false
# A door only fires while nothing was standing in it as of the last physics step: a warp lands
# the player beside their destination door (and a streamed-in door can materialise right under
# them), which must not read as walking through it. `_physics_process` runs BEFORE the step
# whose body_entered signals arrive, so `_armed` always describes the frame the body came from.
# Overlap data is empty until the node has been through a step, hence the settle frames.
const _SETTLE_FRAMES := 2

var _armed := false
var _settle := _SETTLE_FRAMES

# Using any door locks EVERY door for a moment: a warp puts the player down beside their twin, and
# a fast enough body can trip a second door before that arrival settles and slip through the pair.
const _COOLDOWN_MS := 1000
static var _last_use_ms := -_COOLDOWN_MS


func _ready() -> void:
	_apply_style()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	body_entered.connect(_on_body_entered)


## Configure this door from a DoorResource (WgEntitySpawner calls this when a room type spawns a
## door as its feature). Untyped param so door.gd keeps no hard dependency on door_resource.gd.
func setup(res) -> void:
	if res == null:
		return
	style = res.style            # setter re-applies the art once in-tree
	target_scene = res.target_scene
	target_slot = res.target_slot


## Which way `body` was walking into this door, as one of the four cardinals — how it was moving
## if it was, else the line it took to reach us. The far door puts it down on its far side facing
## the same way, so holding one direction carries you through instead of bouncing you back.
func _heading_of(body: Node2D) -> Vector2i:
	var v: Vector2 = body.velocity if "velocity" in body else Vector2.ZERO
	if v.length_squared() < 1.0:
		v = global_position - body.global_position
	if absf(v.x) >= absf(v.y):
		return Vector2i(1 if v.x >= 0.0 else -1, 0)
	return Vector2i(0, 1 if v.y >= 0.0 else -1)


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
	if target_slot != Vector2i.MAX:
		_armed = false   # re-arms once the player is clear of it, so the door works both ways
		_last_use_ms = Time.get_ticks_msec()
		GlobalEvent.warp_requested.emit(target_slot, body, _heading_of(body))
		return
	if _used:
		return
	if not target_scene:
		push_warning("Door at %s has no target_scene" % global_position)
		return
	_used = true
	_last_use_ms = Time.get_ticks_msec()
	SceneManager.go_to(target_scene)
