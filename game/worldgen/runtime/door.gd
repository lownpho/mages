@tool
class_name Door
extends Area2D

## A generic scene-transition trigger. Drop one anywhere — by hand in a scene or
## spawned by the world generator — point it at a `target_scene`, pick a `style`
## for the art, and walking the player onto it switches scenes.
##
## Every door in the game (dungeon entrance, dungeon floor stairs, tutorial exit)
## is this one scene: only the exported data differs.

## Art variants packed in doors.png, one 16×16 frame each (left → right).
enum Style { WOOD, HEDGE, CAVE, PORTAL, STAIRS }

const _FRAME_W := 16

@export var style := Style.WOOD: # Runs on assignment so the editor preview tracks the choice.
	set(value):
		style = value
		_apply_style()

## The scene to switch to when the player steps on this door. Leave null to place
## a door before its destination exists; it just warns and stays put when used.
@export var target_scene: PackedScene

# Guards against firing twice while the deferred scene change is pending.
var _used := false


func _ready() -> void:
	_apply_style()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)


func _apply_style() -> void:
	if not is_node_ready():
		return
	$Sprite2D.region_rect.position.x = style * _FRAME_W


func _on_body_entered(_body: Node2D) -> void:
	if _used:
		return
	if not target_scene:
		push_warning("Door at %s has no target_scene" % global_position)
		return
	_used = true
	SceneManager.go_to(target_scene)
