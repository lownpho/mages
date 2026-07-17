extends Node2D

## Blink: teleports the caster to the cursor (clamped to range_tiles) and leaves
## an arcane-implosion VFX at the spot it vacated. Player-only utility — no
## damage, no collision. The VFX node stays at the departure point and frees
## itself when the one-shot animation ends; the caster has already moved.

var data: BlinkResource
var caster: CharacterBody2D

func setup(spell: SpellResource, p_caster: Node2D) -> void:
	data = spell
	caster = p_caster
	var origin := caster.global_position
	var to_cursor := caster.get_global_mouse_position() - origin
	var max_px := data.range_tiles * GameConstants.PX_PER_TILE
	if to_cursor.length() > max_px:
		to_cursor = to_cursor.normalized() * max_px
	caster.global_position = origin + to_cursor
	# The VFX marks where the player *was*, so it stays put — root has an
	# identity transform, so global_position is set straight from the origin.
	global_position = origin

func _ready() -> void:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	sprite.animation_finished.connect(queue_free)
	sprite.play("vanish")
