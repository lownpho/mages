extends Node
## Proof of the unified caster: a plain enemy (sproutling) casts the PLAYER's own
## heal and fireball spell resources through the same SpellCaster the player uses —
## nothing distinguishes a "weapon" from a spell, and any caster can cast any
## spell. Heal raises the creature's own health; fireball produces an enemy-layer
## bullet. Run:
##   godot --headless --path game res://tests/test_any_caster.tscn

const SPROUTLING := preload("res://characters/enemies/sproutling/sproutling.tscn")
const HEAL := "res://characters/player/spells/heal/heal1.tres"
const FIREBALL := "res://characters/player/spells/fireball/fireball1.tres"
const THWOMP := "res://characters/player/spells/thwomp/thwomp3.tres"
const BWOOM := "res://characters/player/spells/bwoom/bwoom2.tres"
const BWOOM_SCRIPT := "res://characters/player/spells/bwoom/bwoom.gd"
const GNARLKING_CHARGE := "res://characters/enemies/gnarlking/gnarlking_charge.tres"

var fails: Array[String] = []
var _enemy_bullets := 0

func _ready() -> void:
	get_tree().root.child_entered_tree.connect(func(n: Node) -> void:
		if n is BaseBullet and n.collision_layer == GameConstants.LAYER_ENEMY_BULLETS:
			_enemy_bullets += 1)

	var enemy := SPROUTLING.instantiate()
	add_child(enemy)
	await get_tree().physics_frame
	# Wake it (headless never renders, so the off-screen sleeper never ticks). No
	# target is placed, so its own AI stays Idle and never auto-fires — the only
	# casts are the ones we issue below.
	for child in enemy.get_children():
		if child is VisibleOnScreenEnabler2D:
			child.queue_free()
	enemy.process_mode = Node.PROCESS_MODE_INHERIT
	var caster: SpellCaster = enemy.get_node("Caster")

	# 1) The enemy casts the player's heal spell and heals ITSELF.
	enemy.health = 1
	caster.cast(load(HEAL))  # heal1 has cast_time 0.8
	await _wait(1.1)
	if enemy.health <= 1:
		fails.append("creature cast heal but its health did not rise (%d)" % enemy.health)

	# 2) The enemy casts the player's fireball spell → an enemy-layer bullet.
	_enemy_bullets = 0
	caster.cast(load(FIREBALL), Vector2.RIGHT)  # fireball1 has cast_time 0.5
	await _wait(0.9)
	if _enemy_bullets == 0:
		fails.append("creature cast fireball but produced no enemy-layer bullet")

	# 3) Thwomp — the gnarlking's ground slam. It resolves its own AoE rather than firing
	# bullets, so nothing else in the suite would notice it landing on nobody: it sweeps
	# CastContext.target_groups, which for a creature is the player side. Damage falls off
	# with distance and the shove rides the same curve.
	var near := _victim(Vector2(12, 0))
	var far := _victim(Vector2(200, 0))
	# The stubs prove the pulse dispatches by capability; the REAL player is what has to
	# answer it. debug_never_die: a lethal slam would call game_over() and wipe the save.
	var player: CharacterBody2D = preload("res://characters/player/player.tscn").instantiate()
	player.debug_never_die = true
	player.position = Vector2(0, 12)
	add_child(player)
	var player_at := player.global_position
	caster.cast(load(THWOMP), Vector2.RIGHT)
	await _wait(0.5)
	if player.global_position.is_equal_approx(player_at):
		fails.append("thwomp shoved the stubs but the real player never moved")
	player.queue_free()
	if near.health >= 100:
		fails.append("creature cast thwomp but the target beside it took nothing")
	if far.health < 100:
		fails.append("thwomp reached a target well outside its radius")
	if near.knocked == Vector2.ZERO:
		fails.append("thwomp damaged the target but never shoved it")
	near.queue_free()
	far.queue_free()

	# 4) Bwoom — a channel, and the only spell whose damage is decided at RELEASE (one
	# ScalingProfile per tick held). SpellCaster caps the channel at cast_time and calls
	# channel_released itself, so a creature charges and looses it with no button involved.
	var balls: Array[Node] = []
	var watch := func(n: Node) -> void:
		if n.get_script() == load(BWOOM_SCRIPT):
			balls.append(n)
	get_tree().root.child_entered_tree.connect(watch)
	caster.cast(load(BWOOM), Vector2.RIGHT)
	var bwoom: BwoomResource = load(BWOOM)
	await _wait(bwoom.cast_time + 0.4)
	get_tree().root.child_entered_tree.disconnect(watch)
	if balls.is_empty():
		fails.append("creature cast bwoom but no charged ball appeared")
	elif not is_instance_valid(balls[0]):
		fails.append("the bwoom ball vanished instead of launching")
	else:
		if balls[0].get_damage() <= 0:
			fails.append("the launched bwoom ball carries no damage")
		if balls[0].velocity == Vector2.ZERO:
			fails.append("the bwoom channel capped but the ball never launched")
		if balls[0].collision_layer != GameConstants.LAYER_ENEMY_BULLETS:
			fails.append("an enemy's bwoom launched on layer %d, not the enemy bullet layer"
				% balls[0].collision_layer)
		balls[0].queue_free()

	await _charge_runs_through(enemy, caster)
	await _owl_dies_charging()

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)

# 5) A charge straight through its target: the bark peels off both flanks and misses a body
# dead on the line, so the run itself has to land the hit — once, and not after the dash.
func _charge_runs_through(enemy: Creature, caster: SpellCaster) -> void:
	var spell: ChargeDashResource = load(GNARLKING_CHARGE)
	var hits: Array[int] = []
	var hb: Area2D = load("res://components/hurtbox.tscn").instantiate()
	hb.collision_mask = GameConstants.LAYER_ENEMY_BULLETS
	hb.radius = 3.5
	hb.position = enemy.global_position + Vector2(48, 0)
	hb.hurt.connect(func(dmg: int, src: Node) -> void:
		if src is DamageZone:
			hits.append(dmg))
	add_child(hb)
	if not caster.cast(spell, Vector2.RIGHT):
		fails.append("creature could not cast the gnarlking's charge")
	await _wait(spell.cast_time + spell.dash_duration + 0.3)
	var want: int = spell.contact_damage.compute(0, 0, 0)
	if hits.size() != 1 or hits[0] != want:
		fails.append("a charge straight through its target hit it %s, want one %d" % [hits, want])
	for child in enemy.get_children():
		if child is DamageZone:
			fails.append("the charge's contact hit outlived the dash")
	hb.queue_free()

# 6) An owl killed mid-charge takes its Bwoom ball with it: a channel is the caster holding
# the spell, so with the caster gone there is nothing left to loose it.
func _owl_dies_charging() -> void:
	# A body on the player layer, so the owl's LOS probe has something to see.
	var target := CharacterBody2D.new()
	target.collision_layer = 16
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	target.add_child(shape)
	target.add_to_group("player")
	target.position = Vector2(1024, 0)
	add_child(target)
	var owl: Creature = load("res://characters/enemies/owl/owl.tscn").instantiate()
	owl.position = Vector2(1000, 0)
	add_child(owl)
	await get_tree().physics_frame
	for child in owl.get_children():
		if child is VisibleOnScreenEnabler2D:
			child.queue_free()
	owl.process_mode = Node.PROCESS_MODE_INHERIT
	var balls: Array[Node] = []
	var watch := func(n: Node) -> void:
		if n.get_script() == load(BWOOM_SCRIPT):
			balls.append(n)
	get_tree().root.child_entered_tree.connect(watch)
	var deadline := Time.get_ticks_msec() + 5000
	while balls.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	get_tree().root.child_entered_tree.disconnect(watch)
	if balls.is_empty():
		fails.append("the owl never started charging its bwoom")
	else:
		await _wait(0.2)
		owl.die()
		await _wait(0.1)
		if is_instance_valid(balls[0]):
			fails.append("the owl died mid-charge but its bwoom ball stayed behind")
			balls[0].queue_free()
	if is_instance_valid(owl):
		owl.queue_free()
	target.queue_free()

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

# A stand-in for whatever an enemy hunts: in the player group with the `hurtbox` and
# `apply_knockback` capabilities Thwomp reaches for, and nothing else.
func _victim(at: Vector2) -> Node2D:
	var node := preload("res://tests/support/thwomp_victim.gd").new()
	node.position = at
	node.add_to_group("player")
	add_child(node)
	return node
