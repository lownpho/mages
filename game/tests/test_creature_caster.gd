extends Node
## Headless creature-caster smoke: a sproutling (whose attack is a BulletSpell
## cast through the same unified SpellCaster the player uses) sees a player-group
## target and produces enemy-layer bullets through the same bullet_spell effect
## the player uses. Run:
##   godot --headless --path game res://tests/test_creature_caster.tscn

const SPROUTLING := preload("res://characters/enemies/sproutling/sproutling.tscn")

var _enemy_bullets := 0

func _ready() -> void:
	get_tree().root.child_entered_tree.connect(func(n: Node) -> void:
		if n is BaseBullet and n.collision_layer == GameConstants.LAYER_ENEMY_BULLETS:
			_enemy_bullets += 1)
	# A body on the Player physics layer, in the player group, so the detect
	# probe both collides with and recognises it.
	var target := CharacterBody2D.new()
	target.collision_layer = 16
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	target.add_child(shape)
	target.add_to_group("player")
	target.position = Vector2(40, 0)
	add_child(target)
	var enemy := SPROUTLING.instantiate()
	enemy.position = Vector2.ZERO
	add_child(enemy)
	# Creatures sleep off-screen via a VisibleOnScreenEnabler2D, and headless has
	# no rendering, so nothing is ever "on screen" — strip it and force the
	# creature awake or the AI never ticks.
	await get_tree().physics_frame
	for child in enemy.get_children():
		if child is VisibleOnScreenEnabler2D:
			child.queue_free()
	enemy.process_mode = Node.PROCESS_MODE_INHERIT
	# Sproutling: Idle -> sees player -> Attack; the wind-up anim's release
	# frame casts. Give it a generous window of sim time.
	var deadline := Time.get_ticks_msec() + 15000
	while _enemy_bullets == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	if _enemy_bullets > 0:
		print("ALL PASS")
	else:
		print("FAILED: 1")
		print("  FAIL: converted enemy never fired an enemy-layer bullet")
	get_tree().quit(0 if _enemy_bullets > 0 else 1)
