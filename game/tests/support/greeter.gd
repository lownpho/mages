extends Area2D
## A reactive Object for generation tests: it greets the first body to walk up to it, and only
## welcomes it back after that. Having greeted is its Object state, so it survives its chunk
## unloading and setup restores it.

var state: Dictionary = {}


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func setup(data: Dictionary) -> void:
	state = data.state


func has_greeted() -> bool:
	return state.get("greeted", false)


func _on_body_entered(_body: Node2D) -> void:
	state["greeted"] = true
