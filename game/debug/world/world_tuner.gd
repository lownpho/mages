class_name WorldTuner
extends RefCounted
## State model behind the integrated World debug tab. Authored, applied and pending values are kept
## separately: editing never mutates the live graph, Save never silently rebuilds it, and Revert
## always means the last authored value even after a prior Rebuild.

const KNOBS: Array[StringName] = [
	&"room_size", &"border_warp", &"loops", &"shortcuts", &"passage_width", &"rockiness",
]
const RADII: Array[StringName] = [&"spawn", &"boss", &"miniboss", &"rare"]

var content: WorldContent
var world_seed := 0
var plan: WorldPlan
var graph: WorldGraph

## Biome -> knob -> value at the last authored save, in the live graph, and in the controls.
var authored: Dictionary[StringName, Dictionary] = {}
var applied: Dictionary[StringName, Dictionary] = {}
var pending: Dictionary[StringName, Dictionary] = {}
var applied_radii: Dictionary[StringName, int] = {}
var pending_radii: Dictionary[StringName, int] = {}

var last_invalidated_biomes: Dictionary[StringName, bool] = {}
var last_plan_invalidated := false
## Milliseconds for the most recent plan and graph stages.
var timings := {"plan_ms": 0.0, "graphs_ms": 0.0, "total_ms": 0.0}


func setup(world_content: WorldContent, seed_value: int, world_plan: WorldPlan,
		world_graph: WorldGraph) -> void:
	content = world_content
	world_seed = seed_value
	plan = world_plan
	graph = world_graph
	authored.clear()
	applied.clear()
	pending.clear()
	for biome_id in content.biome_ids():
		var values := _resource_values(content.biomes[biome_id])
		authored[biome_id] = values.duplicate()
		applied[biome_id] = values.duplicate()
		pending[biome_id] = values.duplicate()
	applied_radii.assign(plan.radii if plan != null else WorldPlan.DEFAULT_RADII)
	pending_radii.assign(applied_radii)


func set_knob(biome_id: StringName, knob: StringName, value: Variant) -> void:
	assert(pending.has(biome_id) and KNOBS.has(knob))
	pending[biome_id][knob] = value
	_disable_save("spatial knob edited")


func revert_knob(biome_id: StringName, knob: StringName) -> void:
	assert(authored.has(biome_id) and KNOBS.has(knob))
	pending[biome_id][knob] = authored[biome_id][knob]


func set_radius(kind: StringName, value: int) -> void:
	assert(RADII.has(kind))
	pending_radii[kind] = clampi(value, WorldPlan.RADIUS_MIN, WorldPlan.RADIUS_MAX)
	_disable_save("set-piece radius edited")


func revert_radius(kind: StringName) -> void:
	assert(RADII.has(kind))
	pending_radii[kind] = WorldPlan.DEFAULT_RADII[kind]


func is_pending(biome_id: StringName, knob: StringName) -> bool:
	return pending[biome_id][knob] != applied[biome_id][knob]


func differs_from_authored(biome_id: StringName, knob: StringName) -> bool:
	return pending[biome_id][knob] != authored[biome_id][knob]


func radius_is_pending(kind: StringName) -> bool:
	return pending_radii[kind] != applied_radii[kind]


func changed_biomes() -> Dictionary[StringName, bool]:
	var changed: Dictionary[StringName, bool] = {}
	for biome_id in pending:
		for knob in KNOBS:
			if is_pending(biome_id, knob):
				changed[biome_id] = true
				break
	return changed


func has_pending() -> bool:
	return not changed_biomes().is_empty() or RADII.any(func(kind: StringName) -> bool:
		return radius_is_pending(kind))


func unsaved_biomes() -> Array[StringName]:
	var out: Array[StringName] = []
	for biome_id in pending:
		if KNOBS.any(func(knob: StringName) -> bool:
			return differs_from_authored(biome_id, knob)):
			out.append(biome_id)
	return out


## Applies every pending control value. Radius edits make a new World plan; ordinary knob edits
## retain the plan and reuse every unaffected Biome's macro-cell graphs.
func rebuild() -> WorldGraph:
	last_invalidated_biomes = changed_biomes()
	last_plan_invalidated = RADII.any(func(kind: StringName) -> bool:
		return radius_is_pending(kind))
	if last_invalidated_biomes.is_empty() and not last_plan_invalidated:
		return graph
	var old_values := _applied_resource_values()
	_apply_pending_to_resources()
	var started := Time.get_ticks_usec()
	var next_plan := plan
	if last_plan_invalidated:
		next_plan = WorldPlanner.plan(content, world_seed, pending_radii)
	var planned := Time.get_ticks_usec()
	var next_graph := WorldGraph.build(next_plan) if last_plan_invalidated else \
			WorldGraph.rebuild(next_plan, graph, last_invalidated_biomes)
	var finished := Time.get_ticks_usec()
	if next_graph == null:
		_restore_resource_values(old_values)
		return null
	plan = next_plan
	graph = next_graph
	for biome_id in pending:
		applied[biome_id] = pending[biome_id].duplicate()
	applied_radii.assign(pending_radii)
	timings = {
		"plan_ms": (planned - started) / 1000.0,
		"graphs_ms": (finished - planned) / 1000.0,
		"total_ms": (finished - started) / 1000.0,
	}
	return graph


## Starts a new Run from spawn with the current controls applied. Inventory is deliberately outside
## this model and therefore survives. A seed change always invalidates the whole plan and graph.
func reseed(seed_value: int) -> WorldGraph:
	var old_seed := world_seed
	var old_values := _applied_resource_values()
	world_seed = seed_value if seed_value != 0 else 1
	_disable_save("World seed edited")
	_apply_pending_to_resources()
	var started := Time.get_ticks_usec()
	var next_plan := WorldPlanner.plan(content, world_seed, pending_radii)
	var planned := Time.get_ticks_usec()
	var next_graph := WorldGraph.build(next_plan)
	var finished := Time.get_ticks_usec()
	if next_graph == null:
		world_seed = old_seed
		_restore_resource_values(old_values)
		return null
	plan = next_plan
	graph = next_graph
	for biome_id in pending:
		applied[biome_id] = pending[biome_id].duplicate()
	applied_radii.assign(pending_radii)
	last_invalidated_biomes.clear()
	for biome_id in content.biome_ids():
		last_invalidated_biomes[biome_id] = true
	last_plan_invalidated = true
	timings = {
		"plan_ms": (planned - started) / 1000.0,
		"graphs_ms": (finished - planned) / 1000.0,
		"total_ms": (finished - started) / 1000.0,
	}
	return graph


## Writes the six Biome knobs exactly as the controls show them, without changing what the live
## graph uses. Radius and Challenge controls are intentionally not authored here.
func save_changed() -> Dictionary[StringName, Error]:
	var errors: Dictionary[StringName, Error] = {}
	for biome_id in unsaved_biomes():
		var resource := content.biomes[biome_id]
		var live := _resource_values(resource)
		for knob in KNOBS:
			resource.set(knob, pending[biome_id][knob])
		var error := ResourceSaver.save(resource, resource.resource_path)
		for knob in KNOBS:
			resource.set(knob, live[knob])
		if error == OK:
			authored[biome_id] = pending[biome_id].duplicate()
		else:
			errors[biome_id] = error
	return errors


func zone_totals(biome_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for zone_id in content.zone_ids(biome_id):
		var zone: ZoneResource = content.zones[biome_id][zone_id]
		out.append({"id": zone_id, "route_rooms": zone.route_rooms, "rooms": zone.room_count})
	return out


func biome_totals(biome_id: StringName) -> Dictionary:
	return {"zones": content.zone_count(biome_id), "route_rooms": content.route_rooms(biome_id),
			"rooms": content.room_count(biome_id)}


func _resource_values(resource: BiomeResource) -> Dictionary:
	var out := {}
	for knob in KNOBS:
		out[knob] = resource.get(knob)
	return out


func _applied_resource_values() -> Dictionary[StringName, Dictionary]:
	var out: Dictionary[StringName, Dictionary] = {}
	for biome_id in content.biome_ids():
		out[biome_id] = _resource_values(content.biomes[biome_id])
	return out


func _apply_pending_to_resources() -> void:
	for biome_id in pending:
		for knob in KNOBS:
			content.biomes[biome_id].set(knob, pending[biome_id][knob])


func _restore_resource_values(values: Dictionary[StringName, Dictionary]) -> void:
	for biome_id in values:
		for knob in KNOBS:
			content.biomes[biome_id].set(knob, values[biome_id][knob])


func _disable_save(reason: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var state := tree.root.get_node_or_null("GameState")
		if state != null:
			state.disable_run_saving(reason)
