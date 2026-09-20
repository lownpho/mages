@tool
class_name Sign
extends Area2D

## A Sign. When the player walks up to it, its message floats above. A hand-placed one sets
## `message` (empty by default); a World Sign is set up from generated data with its text and the
## Boss or Miniboss Room key reading it reveals. The art is a single blank 16×16 frame for now.

## The text shown above the sign while the player stands on it. Set per placement.
@export_multiline var message := "":
	set(value):
		message = value
		if is_node_ready():
			$Label.text = value

## The Boss or Miniboss Room key reading this Sign reveals on the Map. "" = it marks nothing.
var reveal_key := ""
## The first Room of a Biome this Sign points at, marked on the Map in another colour. "" = none.
var reveal_biome_key := ""

@onready var _label: Label = $Label


func _ready() -> void:
	_label.text = message
	_label.visible = false
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Configure a World Sign from its generated data (ObjectSpawner): its text and reveal key. A Sign
## keeps no Object state; its reveal belongs to the Map.
func setup(data: Dictionary) -> void:
	message = data.text
	reveal_key = data.reveal_key
	reveal_biome_key = data.reveal_biome_key


func _on_body_entered(_body: Node2D) -> void:
	_label.visible = true
	if reveal_key != "":
		GlobalMap.reveal_room(reveal_key)
	if reveal_biome_key != "":
		GlobalMap.reveal_room(reveal_biome_key)


func _on_body_exited(_body: Node2D) -> void:
	_label.visible = false
