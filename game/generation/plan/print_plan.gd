extends Node
## Plans a World headless and prints it: the macro grid with its folded path, then each Biome's
## Zones, quotas, Challenge, set pieces and attachment.
##   godot --headless --path game res://generation/plan/print_plan.tscn -- [seed] [content folder]
## The seed defaults to 1 and the folder to the shipped World. Exits 1 when the content has problems.

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
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	print(plan.describe())
	print("\nPlanned in %.1f ms" % elapsed)
	get_tree().quit(0)
