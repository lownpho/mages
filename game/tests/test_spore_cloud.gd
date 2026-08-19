extends Node
## Guards the spore-cloud primitive the Mycelium is built on: Whumf lays a connected field,
## the field ticks, and light spends it. The one rule with teeth is that a detonation
## hits each victim ONCE however many clouds it is standing in — the chain buys area, not a
## bigger hit — and that lighting a fuse hunts the DETONATOR's enemies, so the player can
## never blow themselves up on the dungeon's own floor.
##   godot --headless --path game res://tests/test_spore_cloud.tscn

const WHUMF_DIR := "res://characters/player/spells/whumf/"
const CLOUD := preload("res://characters/player/spells/whumf/spore_cloud.tscn")
const VICTIM := preload("res://tests/support/thwomp_victim.gd")
const PUFFCAP := preload("res://characters/enemies/puffcap/puffcap.tscn")
const SPITTER := preload("res://characters/enemies/sporespitter/sporespitter.tscn")

const SKILL := 7
const SPEED := 11
const DEFENCE := 5

var _fails: Array[String] = []

func _ready() -> void:
	await _check_field_laid()
	await _check_ticks()
	await _check_blast_lands_once()
	await _check_an_enemy_field_is_inert()
	await _check_light_lights_it()
	await _check_a_puffcap_is_its_own_payload()
	await _check_a_lob_plants_where_it_lands()

	if _fails.is_empty():
		print("ALL PASS")
	else:
		for f in _fails:
			print("  FAIL: ", f)
		print("FAILED: %d" % _fails.size())
	get_tree().quit()

# A ring plus the one under the caster, all on the player's side, all close enough to their
# neighbours to chain — a field that doesn't touch itself is six separate spells.
func _check_field_laid() -> void:
	var spell := _whumf()
	await _cast(spell, Vector2.ZERO)
	var clouds := _clouds()
	if clouds.size() != spell.ring_clouds + 1:
		_fails.append("whumf laid %d clouds, expected %d"
			% [clouds.size(), spell.ring_clouds + 1])
	for cloud in clouds:
		if cloud.foe:
			_fails.append("a player's cloud came out foe-coloured")
		if cloud.target_groups != ["enemies"]:
			_fails.append("player cloud hunts %s" % [cloud.target_groups])
		if cloud.blast_damage <= cloud.tick_damage:
			_fails.append("blast (%d) is no bigger than a tick (%d)"
				% [cloud.blast_damage, cloud.tick_damage])
	_clear()

func _check_ticks() -> void:
	var spell := _whumf()
	var victim := _victim(Vector2(6, 0), "enemies")
	await _cast(spell, Vector2.ZERO)
	for _i in 45:  # past one TICK_INTERVAL
		await get_tree().physics_frame
	if victim.health >= 100:
		_fails.append("standing in the field cost nothing")
	victim.free()
	_clear()

# The reason detonate() collects a victim set instead of letting each cloud fire: at
# Whumf's spread a body sits inside two or three patches at once, and one blast per patch
# would make the combo delete anything it touched.
func _check_blast_lands_once() -> void:
	var spell := _whumf()
	var victim := _victim(Vector2(6, 0), "enemies")
	await _cast(spell, Vector2.ZERO)
	var clouds := _clouds()
	var overlapping := 0
	for cloud in clouds:
		if cloud.covers(victim.global_position):
			overlapping += 1
	if overlapping < 2:
		_fails.append("victim only stood in %d cloud(s) — the test proves nothing" % overlapping)
	var blast: int = clouds[0].blast_damage
	clouds[0].detonate(["enemies"])
	if victim.health != 100 - blast:
		_fails.append("blast took %d, one blast is %d" % [100 - victim.health, blast])
	for cloud in clouds:
		if cloud.covers(cloud.global_position):
			_fails.append("a cloud in the field survived the chain")
	victim.free()
	_clear()

# Detonation is the player's own kit spending the player's own spores. The dungeon's field is
# inert: asked directly it refuses, and a blast in a patch touching it does not spend it
# either — so an enemy's floor stays a hazard to cross rather than a bomb it handed you.
func _check_an_enemy_field_is_inert() -> void:
	var enemy := _victim(Vector2(2, 0), "enemies")
	var player := _victim(Vector2(-2, 0), "player")
	var theirs := _cloud(Vector2.ZERO, true, ["player"])
	await get_tree().physics_frame
	theirs.detonate(["enemies"])
	if enemy.health != 100:
		_fails.append("an enemy's cloud paid out a blast (%d)" % enemy.health)
	if player.health != 100:
		_fails.append("lighting an enemy cloud hurt the player (%d)" % player.health)
	if not theirs.covers(theirs.global_position):
		_fails.append("an enemy's cloud spent itself on a refused detonation")

	# Ours laid right on top of theirs: our blast pays out and their patch is untouched.
	var ours := _cloud(Vector2(4, 0), false, ["enemies"])
	await get_tree().physics_frame
	ours.detonate(["enemies"])
	if enemy.health != 70:
		_fails.append("our own cloud didn't pay out (%d)" % enemy.health)
	if player.health != 100:
		_fails.append("our own blast hit the player (%d)" % player.health)
	if not theirs.covers(theirs.global_position):
		_fails.append("the chain crossed sides and spent the enemy's field")
	enemy.free()
	player.free()
	_clear()

func _cloud(at: Vector2, foe: bool, groups: Array) -> SporeCloud:
	var cloud: SporeCloud = CLOUD.instantiate()
	cloud.position = at
	cloud.foe = foe
	cloud.target_groups = groups
	cloud.blast_damage = 30
	add_child(cloud)
	return cloud

# The wiring the whole mechanic hangs off: a Zaap bullet flown across your own cloud lights
# it, a bullet that carries no light flies straight over, and light crossing an ENEMY patch
# leaves it alone — the end-to-end form of the player-only rule. Detonating through the API is
# not the same claim: the fuse is only lit if the marker behaviour is on Zaap's bullet.
func _check_light_lights_it() -> void:
	const ZAAP := "res://characters/player/spells/zaap/zaap2.tres"
	for case: Array in [[ZAAP, false, true],
						["res://characters/player/spells/pew/pew2.tres", false, false],
						[ZAAP, true, false]]:
		var spell_path: String = case[0]
		var foe: bool = case[1]
		var lights: bool = case[2]
		var victim := _victim(Vector2(40, 0), "enemies")
		var cloud := _cloud(Vector2(40, 0), foe, ["enemies"])
		await get_tree().physics_frame

		var spell: BulletSpellResource = load(spell_path)
		var caster := _stub(Vector2.ZERO)
		var ctx := CastContext.new(spell, caster)
		var bullet: BaseBullet = ctx.spawn_bullet(spell.bullet, Vector2.RIGHT, Vector2.ZERO)
		for _i in 30:
			await get_tree().physics_frame

		# A lit cloud pops and frees itself inside the flash, so "gone" is a lit cloud too.
		var lit := not is_instance_valid(cloud) or not cloud.covers(cloud.global_position)
		if lit != lights:
			_fails.append("%s %s %s cloud" % [spell_path.get_file(),
				"lit" if lit else "flew over", "an enemy's" if foe else "our own"])
		# The blast is the proof it actually went off, not just that the patch vanished.
		if lights and victim.health != 70:
			_fails.append("zaap lit the cloud but nothing took the blast (%d)" % victim.health)
		if is_instance_valid(bullet):
			bullet.free()
		caster.free()
		victim.free()
		_clear()

# The enemy side of the same spell: a foe-coloured field where it stood, hunting the player —
# and the puffcap gone with it, because a mine IS its payload. Sized off the pop's own
# ring_clouds rather than a number here, so retuning how much floor a puffcap coats is a
# balance edit and not a test failure; consumes_caster is the part with teeth.
func _check_a_puffcap_is_its_own_payload() -> void:
	var spell: WhumfResource = load("res://characters/enemies/puffcap/puffcap_pop.tres")
	var puffcap: Creature = PUFFCAP.instantiate()
	add_child(puffcap)
	await get_tree().physics_frame
	var effect: Node = spell.effect_scene.instantiate()
	effect.setup(spell, puffcap)
	add_child(effect)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var clouds := _clouds()
	if clouds.size() != spell.ring_clouds + 1:
		_fails.append("a puffcap popped into %d clouds, expected %d"
			% [clouds.size(), spell.ring_clouds + 1])
	for cloud in clouds:
		if not cloud.foe:
			_fails.append("a puffcap's cloud came out player-coloured")
		if not "player" in cloud.target_groups:
			_fails.append("a puffcap's cloud hunts %s" % [cloud.target_groups])
	if is_instance_valid(puffcap) and not puffcap.is_queued_for_deletion():
		_fails.append("the puffcap outlived its own pop")
		puffcap.free()
	_clear()

# The other way spores reach the floor: a lob leaves its patch wherever the shot stopped, not
# where it was fired. That is how something rooted paints ground it can't stand on, so the
# patch landing under the caster instead of downrange is the failure that matters.
func _check_a_lob_plants_where_it_lands() -> void:
	var spell: BulletSpellResource = load("res://characters/enemies/sporespitter/sporespitter_lob.tres")
	var spitter: Creature = SPITTER.instantiate()
	add_child(spitter)
	await get_tree().physics_frame
	var ctx := CastContext.new(spell, spitter)
	var bullet: BaseBullet = ctx.spawn_bullet(spell.bullet, Vector2.RIGHT, spitter.global_position)
	# Long enough for the blob to clear a patch's own radius — the check below is about the
	# lob landing downrange, and a flight cut shorter than the patch is wide can't show that.
	for _i in 20:
		await get_tree().physics_frame
	var landed := bullet.global_position
	# What a Hurtbox does when the blob arrives; range end and walls run the same expiry.
	bullet.reached_hurtbox()
	await get_tree().physics_frame
	await get_tree().physics_frame

	var clouds := _clouds()
	if clouds.size() != 1:
		_fails.append("a lob left %d clouds, expected 1" % clouds.size())
	for cloud in clouds:
		if not cloud.foe:
			_fails.append("an enemy's lob planted a player patch")
		if not "player" in cloud.target_groups:
			_fails.append("a lobbed patch hunts %s" % [cloud.target_groups])
		if cloud.global_position.distance_to(landed) > SporeCloud.RADIUS:
			_fails.append("the patch landed %.0fpx from the blob"
				% cloud.global_position.distance_to(landed))
		if cloud.global_position.distance_to(spitter.global_position) <= SporeCloud.RADIUS:
			_fails.append("the lob planted its patch under the spitter's own feet")
	if is_instance_valid(bullet):
		bullet.free()
	spitter.free()
	_clear()

# By tier file rather than by name: Whumf has already changed tier once, and a test that
# pins the number goes quiet — it loads null and reports nothing rather than failing.
func _whumf() -> WhumfResource:
	for file in DirAccess.get_files_at(WHUMF_DIR):
		if file.ends_with(".tres"):
			return load(WHUMF_DIR + file)
	_fails.append("no whumf tier ships in " + WHUMF_DIR)
	return null

func _stub(at: Vector2) -> Node2D:
	var caster := Node2D.new()
	caster.set_script(preload("res://tests/support/stub_caster.gd"))
	caster.skill = SKILL
	caster.speed = SPEED
	caster.defence = DEFENCE
	caster.position = at
	add_child(caster)
	return caster

func _cast(spell: SpellResource, at: Vector2) -> void:
	var caster := _stub(at)
	var effect: Node = spell.effect_scene.instantiate()
	effect.setup(spell, caster)
	add_child(effect)
	# The effect adds its clouds deferred, so they land a frame after the cast.
	await get_tree().physics_frame
	await get_tree().physics_frame
	caster.free()

func _victim(at: Vector2, group: String) -> Node2D:
	var node := Node2D.new()
	node.set_script(VICTIM)
	node.position = at
	node.add_to_group(group)
	add_child(node)
	return node

func _clouds() -> Array:
	return get_tree().get_nodes_in_group(SporeCloud.GROUP)

func _clear() -> void:
	for cloud in _clouds():
		cloud.free()
