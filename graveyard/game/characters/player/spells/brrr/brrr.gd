extends Node2D

## Brrr channel effect: an ice patch grows at the cursor point captured at
## button press. Each tick adds 1 tile of burst radius (starting at 1) and one
## base_damage of damage. channel_released() — called by SpellCaster on button
## release or the channel cap — bursts at the current size: damage
## through the Burst DamageZone, the tier icon flying outward as ice shards.

const _SHEET_FRAME := 64.0  # px, one brrr.png frame — the growth art's max diameter
const _SHARD_TIME := 0.25

var data: BrrrResource
var skill: int = 0

var _elapsed := 0.0
var _released := false

@onready var patch: AnimatedSprite2D = $Patch
@onready var burst: DamageZone = $Burst

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	skill = caster.skill
	global_position = caster.get_global_mouse_position()

func _ready() -> void:
	# The last animation frame is this tier's max radius; scale the art to it.
	var max_diameter := (1 + data.ticks) * 2.0 * GameConstants.PX_PER_TILE
	patch.scale = Vector2.ONE * (max_diameter / _SHEET_FRAME)

func _process(delta: float) -> void:
	if _released:
		return
	_elapsed += delta
	var last_frame := patch.sprite_frames.get_frame_count(&"grow") - 1
	patch.frame = clampi(roundi(_elapsed / data.cast_time * last_frame), 0, last_frame)
	# Safety net: if the caster died mid-channel, burst at the cap ourselves.
	if _elapsed > data.cast_time + 0.1:
		channel_released()

func channel_released() -> void:
	if _released:
		return
	_released = true
	# 50 ms grace so a release on the same frame as a tick still counts it.
	var tick_interval := data.cast_time / data.ticks
	var ticks := clampi(int((_elapsed + 0.05) / tick_interval), 0, data.ticks)
	var radius_tiles := 1 + ticks
	burst.damage = ticks * roundi(data.base_damage + skill * data.skill_scaling)
	var shape := CircleShape2D.new()
	shape.radius = radius_tiles * GameConstants.PX_PER_TILE
	$Burst/CollisionShape2D.shape = shape
	$Burst/CollisionShape2D.set_deferred("disabled", false)
	patch.hide()
	_spawn_shards(radius_tiles)
	var cleanup := Timer.new()
	cleanup.one_shot = true
	cleanup.autostart = true
	cleanup.wait_time = _SHARD_TIME + 0.05
	cleanup.timeout.connect(queue_free)
	add_child(cleanup)

func _spawn_shards(radius_tiles: int) -> void:
	var reach := radius_tiles * GameConstants.PX_PER_TILE + GameConstants.PX_PER_TILE
	for i in 4 * radius_tiles:
		var shard := Sprite2D.new()
		shard.texture = data.icon
		add_child(shard)
		var target := Vector2(reach, 0).rotated(randf() * TAU)
		create_tween().tween_property(shard, "position", target, _SHARD_TIME)
