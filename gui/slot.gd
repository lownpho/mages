extends PanelContainer

var empty: bool = true
var item_texture = null

func set_item(texture: Texture2D) -> void:
	empty = false
	item_texture = texture
	$TextureRect.texture = texture

func _ready() -> void:
	pass
