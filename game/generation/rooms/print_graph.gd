extends Node
## Plans and builds a World's room graphs headless and prints every macro cell, Room, role, Passage
## and Object site.
##   godot --headless --path game res://generation/rooms/print_graph.tscn -- [seed] [content folder]
## The seed defaults to 1 and the folder to the shipped World. Exits 1 when the content has problems
## or a macro cell can't be built.

const SHIPPED := "res://generation/world/"


func _ready() -> void:
	var world_seed := 1
	var root := SHIPPED
	for arg in OS.get_cmdline_user_args():
		if arg.is_valid_int():
			world_seed = arg.to_int()
		else:
			root = arg if arg.contains("://") else "res://" + arg
	var content := ContentLoader.load_content(root)
	if not content.is_valid():
		print(content.report())
		get_tree().quit(1)
		return
	var started := Time.get_ticks_usec()
	var plan := WorldPlanner.plan(content, world_seed)
	var planned := Time.get_ticks_usec()
	var graph := WorldGraph.build(plan)
	var built := Time.get_ticks_usec()
	if graph == null:
		get_tree().quit(1)
		return
	print(graph.describe())
	print("\nPlanned in %.1f ms, room graphs in %.1f ms" % [(planned - started) / 1000.0, (built - planned) / 1000.0])
	get_tree().quit(0)
