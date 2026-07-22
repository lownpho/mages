extends Node2D

## Generic summon spawner (Halp, Bzzz, a boss calling adds): lays the minions out in the
## spell's spawn_pattern, injecting each tier's stats, then frees itself — every minion then
## lives on its own. A player's minion is a plain Creature flipped to the player's faction
## (target_groups / bullet layer authored on the minion scene), and the spawner injects the
## per-tier values the spell resource carries: health, spell, sheet, lifetime. A minion that
## brings its own CreatureResource is left entirely alone — that's how the same spell summons
## a boss's adds, which are ordinary roster enemies and already know how to fight.

@export var spread: float = 12.0  ## Lateral spacing between adjacent minions in a fan.

var data: SummonResource
var _origin: Vector2
var _facing: Vector2 = Vector2.RIGHT
var _skill: int = 0
var _speed: int = 0
var _defence: int = 0

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	_origin = caster.global_position
	_facing = caster.get_aim_direction()
	# Snapshot the caster's stats; each minion is stamped with them so its bullet
	# scales exactly as if the player cast it — the minion bullet's own
	# skill/speed/defence_scaling pick which stat grows it (Bzzz=speed, Jimmy=defence).
	_skill = _stat(caster, "skill")
	# Bonus speed only — base_speed is the walk floor, not a power stat (see CastContext).
	_speed = _stat(caster, "speed") - _stat(caster, "base_speed")
	_defence = _stat(caster, "defence")

func _stat(caster: Node2D, key: String) -> int:
	var value = caster.get(key)
	return int(value) if value != null else 0

func _ready() -> void:
	if data.minion_scenes.is_empty():
		queue_free()
		return
	var perp := _facing.orthogonal()
	for i in data.count:
		var minion: Creature = data.minion_scenes[randi() % data.minion_scenes.size()].instantiate()
		# A minion carrying its own CreatureResource is a full creature in its own right (a
		# boss's adds are ordinary roster enemies) — it brings its own health, stats and
		# spells, and stamping the caster's over them would rewrite the enemy.
		if minion.data == null:
			minion.max_health = data.minion_health  # Creature uses this directly when `data` is null
			minion.skill = _skill                   # the player's stats ride the minion so its
			minion.speed = _speed                   # bullet scales through the usual compute()
			minion.defence = _defence
			_inject_spell(minion, data.minion_spell)
			_apply_sheet(minion, data.minion_sheet)
		minion.global_position = _origin + _slot(i, perp)
		# Deferred: a direct add_child to root fails while our own _ready is still
		# busy adding us to the tree.
		get_tree().root.add_child.call_deferred(minion)
		if data.minion_lifetime > 0.0:
			get_tree().create_timer(data.minion_lifetime).timeout.connect(minion.queue_free)
	queue_free()

func _slot(i: int, perp: Vector2) -> Vector2:
	if data.spawn_pattern == 1:  # Ring
		return Vector2(data.spawn_distance, 0).rotated(TAU * i / float(maxi(1, data.count)))
	return _facing * data.spawn_distance + perp * ((i - (data.count - 1) / 2.0) * spread)

# The minion's attack is whichever Cast beat its FSM carries — found by type rather than by
# a hardcoded node name, so a minion scene is free to call its attack state whatever suits.
func _inject_spell(minion: Creature, spell: SpellResource) -> void:
	if spell == null:
		return
	for state in minion.get_node("FSM").get_children():
		if state is Cast:
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
