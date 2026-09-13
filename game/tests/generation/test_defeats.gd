extends Node
## Run defeats at the streamer/spawner/runtime boundary on the small fixture World: individual
## ordinary deaths, reloads before and after the respawn delay, no respawn while the chunk stays
## loaded, full-health survivors of a partly fought encounter, Run-long Fixed-encounter defeat,
## Bestiary counts, kill versus silent removal, unkeyed runtime creatures, and rebuild versus new
## Run. Enemies are killed through the real Creature death. Run:
##   godot --headless --path game res://tests/generation/test_defeats.tscn

## Far enough that a member's chunk passes the streamer's unload hysteresis.
const AWAY_TILES := 100

var _fails: Array[String] = []
var _plain: Dictionary[StringName, bool] = {}


func _ready() -> void:
	var real_bestiary := GlobalBestiary.to_dict()
	GlobalBestiary.restore({})
	var fixture := WorldFixture.small()
	var graph := fixture.graph(fixture.seeds[0])
	var rig := _rig(graph)
	await _test_ordinary(rig)
	await _test_fixed_and_runs(rig)
	rig.viewport.queue_free()
	await get_tree().process_frame
	GlobalBestiary.restore(real_bestiary)
	GlobalBestiary._save()
	if _fails.is_empty():
		print("ALL PASS")
		get_tree().quit(0)
	else:
		for fail in _fails:
			print("  FAIL: ", fail)
		print("FAILED: %d" % _fails.size())
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fails.append(message)


## A one-pixel viewport following a target that is not a player, so enemies stay idle.
func _rig(graph: WorldGraph) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i.ONE
	add_child(viewport)
	var root := Node2D.new()
	viewport.add_child(root)
	var streamer := ChunkStreamer.new()
	root.add_child(streamer)
	var enemies := Node2D.new()
	root.add_child(enemies)
	var spawner := EncounterSpawner.new()
	spawner.streamer = streamer
	spawner.enemies_parent = enemies
	root.add_child(spawner)
	var target := Node2D.new()
	root.add_child(target)
	var camera := Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	target.add_child(camera)
	streamer.build_world(graph)
	var encounters := WorldEncounters.new(graph, streamer.interiors)
	spawner.build_world(encounters, RunDefeats.new())
	streamer.target = target
	return {"viewport": viewport, "streamer": streamer, "spawner": spawner, "enemies": enemies,
			"target": target, "graph": graph, "encounters": encounters}


func _visit(rig: Dictionary, tile: Vector2i) -> void:
	rig.target.position = (Vector2(tile) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
	rig.streamer.prepare()
	await get_tree().process_frame


## Streams the tile's chunk out and back in.
func _reload(rig: Dictionary, tile: Vector2i) -> void:
	var world_tiles: Vector2i = rig.graph.plan.size * WorldPlan.CELL
	var away := tile + Vector2i(AWAY_TILES if tile.x < world_tiles.x >> 1 else -AWAY_TILES, 0)
	await _visit(rig, away)
	_check(not rig.streamer.is_chunk_loaded(rig.streamer.chunk_of(Vector2(tile * GameConstants.PX_PER_TILE))),
			"moving away unloaded the chunk at %s" % tile)
	await _visit(rig, tile)


func _live(rig: Dictionary, key: String) -> Node2D:
	for enemy in rig.enemies.get_children():
		if enemy.get_meta("generated_key", "") == key and not enemy.is_queued_for_deletion():
			return enemy
	return null


## Enemies without a death throe die on the call, with no FSM frames needed.
func _dies_at_once(member: EncounterMember) -> bool:
	var id := member.enemy_id()
	if not _plain.has(id):
		var scene := load("%s/%s.tscn" % [member.enemy.resource_path.get_base_dir(), id]) as PackedScene
		var probe := scene.instantiate()
		_plain[id] = probe.death_state == ""
		probe.free()
	return _plain[id]


func _test_ordinary(rig: Dictionary) -> void:
	var everything := WorldFixture.encounter_world(rig.graph)
	var chosen: GeneratedEncounter = null
	for key in everything.encounters:
		var encounter := everything.encounters[key]
		if encounter.fixed or encounter.members.size() < 3:
			continue
		if encounter.members.slice(0, 3).all(_dies_at_once) and encounter.members[1].enemy.max_health > 1:
			chosen = encounter
			break
	_check(chosen != null, "fixture has an ordinary encounter of three plain members")
	if chosen == null:
		return
	var victim := chosen.members[0]
	var survivor := chosen.members[1]
	var cleared := chosen.members[2]
	var spawner: EncounterSpawner = rig.spawner
	var defeats := spawner.defeats
	var delay: float = rig.graph.plan.content.curve.respawn_delay
	await _visit(rig, chosen.centre)
	for member in [victim, survivor, cleared]:
		_check(_live(rig, member.key) != null, "%s streamed in" % member.key)
	if _live(rig, victim.key) == null or _live(rig, survivor.key) == null or _live(rig, cleared.key) == null:
		return

	# One member dies for real; another is only hurt; the third is removed without dying.
	var id := victim.enemy_id()
	var kills_before := GlobalBestiary.kill_count(id)
	var hurt := _live(rig, survivor.key)
	hurt.health = hurt.max_health - 1
	_live(rig, victim.key).die()
	_live(rig, cleared.key).queue_free()
	await get_tree().process_frame
	_check(defeats.deaths.has(victim.key), "an ordinary death recorded its play time")
	_check(not defeats.deaths.has(survivor.key) and not defeats.deaths.has(cleared.key),
			"only the killed member of the partly fought encounter is recorded")
	_check(not defeats.defeated.has(victim.key), "an ordinary death isn't a Run-long defeat")
	_check(GlobalBestiary.kill_count(id) == kills_before + 1, "the real death counted in the Bestiary")

	# A runtime creature (a summon or split) has no key and leaves no record when it dies.
	var runtime: Node2D = (load("%s/%s.tscn" % [victim.enemy.resource_path.get_base_dir(), id]) as PackedScene).instantiate()
	rig.enemies.add_child(runtime)
	runtime.die()
	await get_tree().process_frame
	_check(defeats.deaths.size() == 1 and defeats.defeated.is_empty(), "an unkeyed runtime death was recorded")
	var counted := GlobalBestiary.kill_count(id)

	# Before the delay a reload brings back the survivor at full health and the silently removed
	# member, but not the dead one.
	await _reload(rig, chosen.centre)
	_check(_live(rig, victim.key) == null, "the dead member respawned before the delay")
	_check(defeats.deaths.has(victim.key), "a reload before the delay kept the death entry")
	var returned := _live(rig, survivor.key)
	_check(returned != null and returned.health == returned.max_health, "the survivor returned at full health")
	_check(_live(rig, cleared.key) != null, "a silently removed member returned on reload")

	# The delay passing while the chunk stays loaded spawns nothing in view.
	defeats.play_time += delay + 1.0
	for _frame in 5:
		await get_tree().process_frame
	_check(_live(rig, victim.key) == null, "the dead member respawned while its chunk stayed loaded")
	_check(defeats.deaths.has(victim.key), "the death entry cleared without a stream-in")

	# The next stream-in after the delay respawns it and forgets the death.
	await _reload(rig, chosen.centre)
	_check(_live(rig, victim.key) != null, "the dead member didn't respawn on stream-in after the delay")
	_check(not defeats.deaths.has(victim.key), "respawning didn't clear the death entry")
	_check(GlobalBestiary.kill_count(id) == counted, "respawning changed the Bestiary")


func _test_fixed_and_runs(rig: Dictionary) -> void:
	var everything := WorldFixture.encounter_world(rig.graph)
	var leader: EncounterMember = null
	for key in everything.members:
		var member := everything.members[key]
		if member.fixed and member.leader and _dies_at_once(member):
			leader = member
			break
	_check(leader != null, "fixture has a plain Fixed-encounter leader")
	if leader == null:
		return
	var spawner: EncounterSpawner = rig.spawner
	await _visit(rig, leader.tile)
	var node := _live(rig, leader.key)
	_check(node != null, "the Fixed leader streamed in")
	if node == null:
		return
	var id := leader.enemy_id()
	var kills_before := GlobalBestiary.kill_count(id)
	node.die()
	await get_tree().process_frame
	_check(spawner.defeats.defeated.has(leader.key) and not spawner.defeats.deaths.has(leader.key),
			"a Fixed-encounter death is a Run-long defeat")
	_check(GlobalBestiary.kill_count(id) == kills_before + 1, "the Fixed death counted in the Bestiary")
	spawner.defeats.play_time += 100_000.0
	await _reload(rig, leader.tile)
	_check(_live(rig, leader.key) == null, "a defeated Fixed leader respawned")

	# A rebuild keeps the Run's defeats; a new Run starts without them.
	spawner.build_world(rig.encounters)
	await get_tree().process_frame
	_check(_live(rig, leader.key) == null, "a rebuild forgot the Run's defeats")
	spawner.build_world(rig.encounters, RunDefeats.new())
	await get_tree().process_frame
	_check(_live(rig, leader.key) != null, "a new Run kept the previous Run's defeat")
