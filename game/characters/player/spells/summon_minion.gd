extends Enemy
class_name SummonMinion

## A summoned ally: a faction-flipped Enemy that hunts the "enemies" group and fires
## player bullets (both set on the scene root). Health, the caster's skill, lifetime,
## the weapon, and the sheet texture are injected by the summon spawner before it enters
## the tree, so one script serves every summon and tier. `data` stays null — we override
## _ready to skip the EnemyResource mirroring and use the injected values instead.
##
## Animation layout (frame regions, counts, durations) is authored in the minion scene's
## SpriteFrames; only the sheet *texture* varies per tier, so we just swap the atlas (see
## `sheet`). All of a summon's tiers share frame size/count/timing — that's the contract.

var sheet: Texture2D = null  ## Per-tier spritesheet; swapped onto the authored frames.
var lifetime: float = 0.0    ## Seconds before the minion expires; 0 = no expiry.

func _ready() -> void:
	if sheet:
		# Deep-copy so this instance's atlas swap can't bleed into other tiers sharing
		# the scene's SpriteFrames, then point every frame at this tier's sheet.
		var frames: SpriteFrames = sprite.sprite_frames.duplicate(true)
		for anim in frames.get_animation_names():
			for i in frames.get_frame_count(anim):
				(frames.get_frame_texture(anim, i) as AtlasTexture).atlas = sheet
		sprite.sprite_frames = frames
	health = max_health
	hurtbox.hurt.connect(_on_hurt)
	# Deferred for the same reason as Enemy._ready: behaviours parent their timers
	# on the first deferred flush, which must land before the FSM starts.
	fsm.start.call_deferred()
	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(queue_free)
