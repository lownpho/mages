extends Area2D
## A fast-travel portal, placed one-per-biome at the biome centre by the specials pass. Stepping
## on it (player body enters) opens a self-contained travel menu listing the graph-adjacent biomes
## only — mirroring the world graph's edges, so long trips are multi-hop. Picking a destination
## teleports the player onto that biome's portal tile and closes the menu. No unlock/discovery
## state: the menu is pure data read from the payload the streamer injected via `setup`.

var _neighbors: Array = []   # [{id:StringName, tile:Vector2i}] — the adjacent biome portals
var _menu: CanvasLayer


func _ready() -> void:
	body_entered.connect(_on_body_entered)


## The streamer's contract: hand the portal its `&"portal"` special payload
## ({node, biome_id, neighbors}). Only the neighbour list is needed at runtime.
func setup(payload: Dictionary) -> void:
	_neighbors = payload.get("neighbors", [])


func _on_body_entered(_body: Node2D) -> void:
	if _menu != null:   # menu already open (or we just arrived here)
		return
	_open_menu()


func _open_menu() -> void:
	_menu = CanvasLayer.new()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	for n in _neighbors:
		var b := Button.new()
		b.text = "Travel to %s" % n.id
		b.pressed.connect(_travel.bind(n.tile))
		box.add_child(b)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_close)
	box.add_child(cancel)

	root.add_child(box)
	_menu.add_child(root)
	add_child(_menu)


func _travel(tile: Vector2i) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var half := GameConstants.PX_PER_TILE / 2.0
		player.global_position = Vector2(tile * GameConstants.PX_PER_TILE) + Vector2.ONE * half
	_close()


func _close() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
