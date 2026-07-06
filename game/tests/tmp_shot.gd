extends Node

const OUT := "/tmp/claude-1000/-home-dario-Workspace-mages/b14bedf6-7305-4d8c-94b4-8223b9c6bad1/scratchpad"

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("3e6b47")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var ui: CanvasLayer = load("res://gui/ui.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	ui.get_node("%BestiaryButton").pressed.emit()
	GlobalEvent.creature_died.emit(GlobalBestiary.load_data(&"hopper"), Vector2.ZERO)
	GlobalEvent.creature_died.emit(GlobalBestiary.load_data(&"fae"), Vector2.ZERO)
	for _i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "/shot_glade.png")
	ui.get_node("%BestiaryPanel").get_node("%NextPage").pressed.emit()
	for _i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "/shot_deepwood.png")
	get_tree().quit()
