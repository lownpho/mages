@tool
class_name Professor
extends Area2D

## A placeholder Professor. When the player walks up to it, a note floats above saying it's away.
## The real Professor checks the player's bestiary progress and rewards an item; this one only
## stands in for it. The art is a tinted player frame for now.

@onready var _label: Label = $Label


func _ready() -> void:
	_label.visible = false
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Configure a World Professor from its generated data (ObjectSpawner). The placeholder reads nothing
## and keeps no Object state.
func setup(_data: Dictionary) -> void:
	pass


func _on_body_entered(_body: Node2D) -> void:
	_label.visible = true


func _on_body_exited(_body: Node2D) -> void:
	_label.visible = false
