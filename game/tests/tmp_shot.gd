extends Control

## Throwaway screenshot harness. Boots the real title screen and shoots the generated backdrop,
## upscaled x4 nearest so 8px art is readable in the output. Must run WINDOWED: --headless renders
## nothing to grab.
##
## Booting title.tscn is save-safe: title.gd only READS the save (has_save, the owned-icon peek),
## and the backdrop is inert by design — no world_ready, no biome_entered, no persist(). See
## test_title_backdrop.

const OUT := "/tmp/claude-1000/-home-dario-Workspace-mages/7b83a6c4-8fee-434a-a6b9-a344eaa2fe99/scratchpad"
const ZOOM := 4


func _ready() -> void:
	add_child(load("res://scenes/title.tscn").instantiate())
	# The streamer loads one chunk per frame on purpose, so give the view time to fill in.
	for _i in 60:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	image.resize(image.get_width() * ZOOM, image.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	image.save_png("%s/title.png" % OUT)
	get_tree().quit()
