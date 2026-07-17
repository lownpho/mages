extends Node
## Instantiates every enemy scene under characters/enemies/<id>/<id>.tscn and lets a few
## frames run, so broken node paths, weapon setup, and FSM wiring fail loudly here instead
## of on first spawn in-game. Run as a scene (autoloads):
##   godot --headless --path game res://tests/test_enemy_scenes.tscn

func _ready() -> void:
	var fails := 0
	var checked := 0
	var dir := DirAccess.open("res://characters/enemies")
	for id in dir.get_directories():
		var path := "res://characters/enemies/%s/%s.tscn" % [id, id]
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			print("  FAIL: %s does not load" % path)
			fails += 1
			continue
		var node: Node = scene.instantiate()
		add_child(node)
		checked += 1
		if node.data == null:
			print("  FAIL: %s carries no CreatureResource" % id)
			fails += 1
		elif node.data.max_health <= 0 or node.data.icon == null:
			print("  FAIL: %s data incomplete (hp/icon)" % id)
			fails += 1
	# Two frames so deferred FSM entry and make_timer adds actually execute.
	await get_tree().process_frame
	await get_tree().process_frame
	print("enemy scenes: %d instantiated" % checked)
	print("ALL PASS" if fails == 0 else "FAILED: %d" % fails)
	get_tree().quit()
