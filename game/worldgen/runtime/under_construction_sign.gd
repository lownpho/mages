@tool
class_name UnderConstructionSign
extends Area2D

## A placeholder marker for an area that isn't built yet. Drop one anywhere — by hand
## or spawned by the world generator as a room's feature — and when the player walks up
## to it, a message floats above telling them the area is under construction and to go
## explore elsewhere. The art is a single blank 16×16 frame for now.

const _DEFAULT_MESSAGE := "The old ammargelluted lonfo is\nworking on this feature, be patient!"

## The text shown above the sign while the player stands on it. Override per placement.
@export_multiline var message := _DEFAULT_MESSAGE:
	set(value):
		message = value
		if is_node_ready():
			$Label.text = value

## Where reading this sign marks a boss on the map: the room origin slot a SignDef's reveal resolved
## to (see SignLinks). Vector2i.MAX = it marks nothing.
var reveal_slot := Vector2i.MAX

@onready var _label: Label = $Label


func _ready() -> void:
	_label.text = message
	_label.visible = false
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Configure from an UnderConstructionResource or a SignDef (WgEntitySpawner calls this when a room
## spawns a sign as a feature). Untyped param to keep no hard dependency on the resource.
func setup(res) -> void:
	if res == null:
		return
	if res.message != "":
		message = res.message
	if "reveal_slot" in res:
		reveal_slot = res.reveal_slot


func _on_body_entered(_body: Node2D) -> void:
	_label.visible = true
	if reveal_slot != Vector2i.MAX:
		GlobalMap.reveal_boss(reveal_slot)


func _on_body_exited(_body: Node2D) -> void:
	_label.visible = false
