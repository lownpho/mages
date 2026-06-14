extends Node2D

## Generic summon spawner (Halp, Bzzz, …): places the minions abreast in front of the
## caster (facing the cursor), injecting each tier's stats and weapon, then frees itself —
## every minion then lives on its own (see summon_minion). The minion scene decides how it
## behaves once spawned (advance and fight, or tether to the caster).

@export var spawn_distance: float = 16.0  ## Distance in front of the caster the fan centres on.
@export var spread: float = 12.0          ## Lateral spacing between adjacent minions.

var data: SummonResource
var _skill: int = 0
var _origin: Vector2
var _facing: Vector2 = Vector2.RIGHT

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	_skill = caster.skill
	_origin = caster.global_position
	_facing = (caster.get_global_mouse_position() - caster.global_position).normalized()

func _ready() -> void:
	var perp := _facing.orthogonal()
	for i in data.count:
		var minion = data.minion_scene.instantiate()
		minion.max_health = data.minion_health
		minion.skill = _skill  # bake the caster's skill so the minion's shots scale with it
		minion.lifetime = data.minion_lifetime
		minion.get_node("FSM/Attack").weapon_data = data.minion_weapon
		minion.sheet = data.minion_sheet  # this tier's spritesheet, swapped onto the authored frames
		var offset := (i - (data.count - 1) / 2.0) * spread
		minion.global_position = _origin + _facing * spawn_distance + perp * offset
		# Deferred: a direct add_child to root fails while our own _ready is still
		# busy adding us to the tree.
		get_tree().root.add_child.call_deferred(minion)
	queue_free()
