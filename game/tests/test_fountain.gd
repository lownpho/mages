extends Node
## Headless fountain smoke test: every biome style resolves its art, a hurt body is
## restored to full and the fountain goes dormant, and a second touch does nothing while
## the cooldown runs. Run:
##   godot --headless --path game res://tests/test_fountain.tscn

const FOUNTAIN := preload("res://worldgen/runtime/fountain.tscn")


class FakePlayer:
	extends CharacterBody2D
	var health := 30
	var max_health := 100


func _ready() -> void:
	var fails: Array[String] = []

	for style in Fountain.Style.values():
		var f: Fountain = FOUNTAIN.instantiate()
		f.style = style
		f.cooldown = 5.0
		add_child(f)
		var sprite: AnimatedSprite2D = f.get_node("AnimatedSprite2D")
		var biome: String = Fountain.Style.keys()[style].to_lower()

		if sprite.animation != &"%s_flow" % biome:
			fails.append("%s: idle art is %s" % [biome, sprite.animation])
		if not sprite.is_playing():
			fails.append("%s: active fountain is not animating" % biome)

		var player := FakePlayer.new()
		add_child(player)
		f._on_body_entered(player)

		if player.health != player.max_health:
			fails.append("%s: healed to %d" % [biome, player.health])
		if sprite.animation != &"%s_dormant" % biome:
			fails.append("%s: spent art is %s" % [biome, sprite.animation])
		if sprite.sprite_frames.get_frame_count(sprite.animation) != 1:
			fails.append("%s: dormant animation has more than one frame" % biome)

		player.health = 10
		f._on_body_entered(player)
		if player.health != 10:
			fails.append("%s: healed again while on cooldown" % biome)

		f.free()
		player.free()

	if fails.is_empty():
		print("ALL PASS")
	else:
		for f2 in fails:
			print("  - ", f2)
		print("FAILED: %d" % fails.size())
	get_tree().quit()
