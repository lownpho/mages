extends Node2D

## Generic summon spawner (Halp, Bzzz, a boss calling adds): lays the minions out in the
## spell's spawn_pattern, injects the per-tier values (health, spell, sheet, lifetime),
## then frees itself. A minion that brings its own CreatureResource is left entirely
## alone — that's how the same spell summons a boss's adds, which are ordinary roster
## enemies and already know how to fight.

@export var spread: float = 12.0  ## Lateral spacing between adjacent minions in a fan.

var data: SummonResource
var ctx: CastContext

# Snapshot of the caster through the usual CastContext, so each minion is stamped with
# its stats and fires exactly as if the caster had cast minion_spell itself — the minion
# bullet's own skill/speed/defence_scaling pick which stat grows it (Bzzz=speed,
# Jimmy=defence).
func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	ctx = CastContext.new(spell, caster)

func _ready() -> void:
	if data.minion_scenes.is_empty():
		queue_free()
		return
	var perp := ctx.aim.orthogonal()
	for i in data.count:
		var minion: Creature = data.minion_scenes[randi() % data.minion_scenes.size()].instantiate()
		# A minion carrying its own CreatureResource is a full creature in its own right (a
		# boss's adds are ordinary roster enemies) — it brings its own health, stats and
		# spells, and stamping the caster's over them would rewrite the enemy.
		if minion.data == null:
			minion.max_health = data.minion_health  # Creature uses this directly when `data` is null
			minion.skill = ctx.skill                # the caster's stats ride the minion so its
			minion.speed = ctx.speed                # bullet scales through the usual compute()
			minion.defence = ctx.defence
			_inject_spell(minion, data.minion_spell)
			_apply_sheet(minion, data.minion_sheet)
		minion.global_position = ctx.origin + _slot(i, perp)
		# Deferred: a direct add_child to root fails while our own _ready is still
		# busy adding us to the tree.
		get_tree().root.add_child.call_deferred(minion)
		if data.minion_lifetime > 0.0:
			get_tree().create_timer(data.minion_lifetime).timeout.connect(minion.queue_free)
	queue_free()

func _slot(i: int, perp: Vector2) -> Vector2:
	if data.spawn_pattern == 1:  # Ring
		return Vector2(data.spawn_distance, 0).rotated(TAU * i / float(maxi(1, data.count)))
	if data.spawn_pattern == 2:  # Queue
		return -ctx.aim * data.spawn_distance * (i + 1)
	return ctx.aim * data.spawn_distance + perp * ((i - (data.count - 1) / 2.0) * spread)

# The minion's attack is whichever Cast beat its FSM carries — found by type rather than by
# a hardcoded node name, so a minion scene is free to call its attack state whatever suits.
# A beat that already carries a spell is left alone, for the same reason a minion with its own
# CreatureResource is: it authored its own fight (Poot and Blops each ladder a plain rung and a
# spore-fed one), and stamping one spell over that would collapse the ladder into its own floor.
func _inject_spell(minion: Creature, spell: SpellResource) -> void:
	if spell == null:
		return
	for state in minion.get_node("FSM").get_children():
		if state is Cast and state.spell == null:
			state.spell = spell
			return

# Swap this tier's spritesheet onto the minion's authored frames, so one minion scene
# serves tiers that look different (e.g. Jimmy's three sizes). Deep-copy first so the
# atlas swap can't bleed into other tiers sharing the scene's SpriteFrames.
func _apply_sheet(minion: Creature, sheet: Texture2D) -> void:
	if not sheet:
		return
	var spr: AnimatedSprite2D = minion.get_node("AnimatedSprite2D")
	var frames: SpriteFrames = spr.sprite_frames.duplicate(true)
	for anim in frames.get_animation_names():
		for f in frames.get_frame_count(anim):
			(frames.get_frame_texture(anim, f) as AtlasTexture).atlas = sheet
	spr.sprite_frames = frames
