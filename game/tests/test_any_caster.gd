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

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
