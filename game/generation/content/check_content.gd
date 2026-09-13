extends Node
## Runs the content load pass on a folder and prints every problem as path:line: message.
##   godot --headless --path game res://generation/content/check_content.tscn -- [content folder]
## The folder defaults to the shipped World. Exits 0 when it loads clean, 1 otherwise.

const SHIPPED := "res://generation/world/"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var root: String = SHIPPED if args.is_empty() else args[0]
	if not root.contains("://"):
		root = "res://" + root
	var content := ContentLoader.load_content(root)
	for error in content.errors:
		print(error)
	if content.is_valid():
		var zones := 0
		for biome_id in content.biome_ids():
			zones += content.zone_count(biome_id)
		print("%s loads clean: %d Biomes, %d Zones, %d Rooms" % [content.root, content.biomes.size(), zones, content.world_room_count()])
	else:
		print("%d problems" % content.errors.size())
	get_tree().quit(0 if content.is_valid() else 1)
