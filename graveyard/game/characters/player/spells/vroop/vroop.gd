extends Node2D

## Vroop: a vortex pinned at the cursor that drags every enemy within pull_radius toward
## its centre — pure crowd control, no damage. A moving channel: it spawns at button
## press (aim locks to the cursor), stays active while you keep moving and
## shooting, and ends on release or the duration cap (cast_time).
## channel_released() frees the node.

const _SPIN := 0.8  # gentle swirl-art spin, radians/sec

var data: VroopResource

var _released := false

@onready var swirl: Sprite2D = $Swirl

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	global_position = caster.get_global_mouse_position()

func _process(delta: float) -> void:
	swirl.rotation += _SPIN * delta

func _physics_process(delta: float) -> void:
	if _released:
		return
	var radius := data.pull_radius_tiles * GameConstants.PX_PER_TILE
	var step := data.pull_speed_tiles * GameConstants.PX_PER_TILE * delta
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as CharacterBody2D
		if body == null:
			continue
		var offset := global_position - body.global_position
		var dist := offset.length()
		if dist > radius or dist < 0.5:
			continue
		# Pull through the physics system, not by assigning position: move_and_collide
		# honours the enemy's collision mask, so they bump into each other and walls and
		# pack around the centre instead of merging into one another.
		body.move_and_collide(offset / dist * minf(step, dist))

func channel_released() -> void:
	if _released:
		return
	_released = true
	queue_free()
