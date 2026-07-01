extends Node
## Group B verify + progress checker for the authored world content. Loads world_graph.tres,
## asserts the data contract (connected graph, valid start, every biome has a required area,
## every encounter well-formed), and prints a readable map of what's authored so far. Run:
##   godot --headless --path game overworld/tests/test_content.tscn

const GRAPH_PATH := "res://overworld/world_graph.tres"
const KIND_NAMES := ["SOLITARY", "PACK", "MIXED"]


func _ready() -> void:
	var fails: Array[String] = []
	var graph: WorldGraph = load(GRAPH_PATH)

	if graph == null:
		print("RESULT: FAIL [could not load %s]" % GRAPH_PATH)
		get_tree().quit(1)
		return

	# Graph-level contract (connected, valid start, required areas, sane edges).
	for e in graph.validate():
		fails.append(e)

	# Per-biome / per-encounter data integrity + the readable report.
	print("=== WORLD GRAPH ===")
	print("nodes: %d   edges: %d   start: %d (%s)" % [
		graph.nodes.size(), graph.edges.size(), graph.start_index,
		_biome_id(graph, graph.start_index)])
	print("adjacency:")
	for i in graph.nodes.size():
		var names: Array[String] = []
		for m in graph.neighbors(i):
			names.append(_biome_id(graph, m))
		print("  %s  --  %s" % [_biome_id(graph, i), ", ".join(names)])

	print("\n=== BIOMES ===")
	for i in graph.nodes.size():
		var biome = graph.nodes[i].biome
		if biome == null:
			continue
		var req := 0
		var opt := 0
		for a in biome.area_set:
			if a.required: req += 1
			else: opt += 1
		var dungeons: Array[String] = []
		for d in biome.dungeon_types:
			dungeons.append(String(d))
		print("\n[%s]  radius~%d  areas: %d required / %d optional  dungeons: %s" % [
			biome.id, biome.target_radius_tiles, req, opt,
			"none" if dungeons.is_empty() else ", ".join(dungeons)])
		if biome.painter == null:
			print("  (no painter yet — wired in Group F)")

		for a in biome.area_set:
			var tags: Array[String] = []
			for t in a.tags:
				tags.append(String(t))
			print("  · %-10s %-9s weight %.1f  roster %d  encounters %d%s" % [
				String(a.type_id),
				"REQUIRED" if a.required else "optional",
				a.weight, a.roster.size(), a.encounters.size(),
				"  tags[%s]" % ", ".join(tags) if not tags.is_empty() else ""])
			if a.roster.is_empty():
				fails.append("area '%s' in '%s' has an empty roster" % [a.type_id, biome.id])
			for enc in a.encounters:
				var reason: String = enc.why_invalid()
				if reason != "":
					fails.append("encounter in '%s/%s' invalid: %s" % [biome.id, a.type_id, reason])
				print("      - %-8s x%d-%d  weight %.1f  entries %d" % [
					KIND_NAMES[enc.kind], enc.count_min, enc.count_max,
					enc.weight, enc.entry_scenes.size()])

	print("\nRESULT: ", "PASS" if fails.is_empty() else "FAIL " + str(fails))
	get_tree().quit(1 if not fails.is_empty() else 0)


func _biome_id(graph: WorldGraph, index: int) -> String:
	if index < 0 or index >= graph.nodes.size() or graph.nodes[index].biome == null:
		return "?"
	return String(graph.nodes[index].biome.id)
