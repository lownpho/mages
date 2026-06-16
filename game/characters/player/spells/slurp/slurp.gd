extends Node2D

## Slurp channel: a lifesteal drain aura. While the spell button is held, every
## tick_interval the player drains every enemy within range_tiles — each takes damage
## and bleeds a red drop of life that streams into the player, healing the caster for
## heal_fraction of the damage dealt. channel_released() — called by SpellCaster on
## button release, mana-out, or the channel cap — stops the drain and frees the node.

const _PulseScene = preload("res://characters/player/spells/slurp/slurp_pulse.tscn")

var data: SlurpResource
var caster: CharacterBody2D
var skill: int = 0

var _released := false

func setup(spell: SpellResource, p_caster: Node2D) -> void:
	data = spell
	caster = p_caster
	skill = p_caster.skill
	global_position = p_caster.global_position

func _ready() -> void:
	var tick := Timer.new()
	tick.wait_time = data.tick_interval
	tick.timeout.connect(_tick)
	tick.autostart = true
	add_child(tick)

func _physics_process(_delta: float) -> void:
	if not _released and is_instance_valid(caster):
		global_position = caster.global_position

func _tick() -> void:
	if _released or not is_instance_valid(caster):
		return
	var damage := roundi(data.base_damage + skill * data.skill_scaling)
	var pulse = _PulseScene.instantiate()
	pulse.position = global_position
	pulse.damage = damage
	pulse.heal_per_hit = roundi(damage * data.heal_fraction)
	pulse.caster = caster
	pulse.build_radius(data.range_tiles * GameConstants.PX_PER_TILE)
	# Deferred: a tick can land on the same frame the node is still being set up.
	get_tree().root.add_child.call_deferred(pulse)

func channel_released() -> void:
	if _released:
		return
	_released = true
	queue_free()
