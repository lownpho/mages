extends Node2D

## Generic summon spawner (Halp, Bzzz, …): places the minions abreast in front of the
## caster (facing the cursor), injecting each tier's stats, then frees itself — every
## minion then lives on its own. A minion is a plain Creature flipped to the player's
## faction (target_groups / bullet layer authored on the minion scene); the spawner only
## injects the per-tier values the spell resource carries: health, weapon, sheet, lifetime.

@export var spawn_distance: float = 16.0  ## Distance in front of the caster the fan centres on.
@export var spread: float = 12.0          ## Lateral spacing between adjacent minions.

var data: SummonResource
var _origin: Vector2
var _facing: Vector2 = Vector2.RIGHT

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	_origin = caster.global_position
	_facing = (caster.get_global_mouse_position() - caster.global_position).normalized()

func _ready() -> void:
	var perp := _facing.orthogonal()
	for i in data.count:
		var minion: Creature = data.minion_scene.instantiate()
		minion.max_health = data.minion_health  # Creature uses this directly when `data` is null
		minion.get_node("FSM/Attack").weapon_data = data.minion_weapon
		_apply_sheet(minion, data.minion_sheet)
		var offset := (i - (data.count - 1) / 2.0) * spread
		minion.global_position = _origin + _facing * spawn_distance + perp * offset
		# Deferred: a direct add_child to root fails while our own _ready is still
		# busy adding us to the tree.
		get_tree().root.add_child.call_deferred(minion)
		if data.minion_lifetime > 0.0:
			get_tree().create_timer(data.minion_lifetime).timeout.connect(minion.queue_free)
	queue_free()

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
