extends Node
class_name SpellCaster

## Casts the spells equipped in GlobalInventory.spell_slots. The generic flow
## lives here — input, cooldown, mana, and the cast-time root (the player FSM's
## "Cast" state). Everything spell-specific lives in the spell's effect scene,
## spawned through the setup(spell, caster) contract (see SpellResource).

const SPELL_ACTIONS = ["spell1", "spell2", "spell3", "spell4"]

@onready var player: CharacterBody2D = get_parent()

var _cooldowns: Dictionary = {}  # SpellResource -> one-shot cooldown Timer
var _cast_timer: Timer
var _pending_spell: SpellResource
var _channel_spell: SpellResource
var _channel_effect: Node
var _channel_action: String
var _channel_drain: float = 0.0  # fractional mana owed by the per-second drain

func _ready() -> void:
	_cast_timer = Timer.new()
	_cast_timer.one_shot = true
	_cast_timer.timeout.connect(_on_cast_time_finished)
	add_child(_cast_timer)

func _unhandled_input(event: InputEvent) -> void:
	for i in SPELL_ACTIONS.size():
		if event.is_action_pressed(SPELL_ACTIONS[i]):
			_try_cast(i)
			return

func _try_cast(slot_index: int) -> void:
	var slot := GlobalInventory.spell_slots.at(slot_index)
	if slot == null or slot.item == null:
		return
	var spell := slot.item as SpellResource
	if spell == null or spell.effect_scene == null:
		return
	# Cooldowns are keyed by the spell itself, not the slot, so moving a spell
	# to another slot mid-cooldown can't dodge it. Tiers are distinct spells.
	var cooldown: Timer = _cooldowns.get(spell)
	if cooldown and not cooldown.is_stopped():
		return
	# can_use_weapon doubles as "free to act": false while focusing or mid-cast.
	if not player.can_use_weapon:
		return
	# A moving channel doesn't enter the Cast state, so can_use_weapon can't
	# block a second cast mid-channel — gate explicitly: one channel at a time.
	if _channel_spell != null:
		return
	if player.mana < spell.mana_cost:
		return

	if spell.channeled:
		# Channeled: mana drains per second instead of upfront; cast_time is
		# the channel cap. The effect spawns at press, so aim locks there.
		if not spell.channel_while_moving:
			player.fsm.transition_to("Cast")
		_channel_spell = spell
		_channel_action = SPELL_ACTIONS[slot_index]
		_channel_drain = 0.0
		_channel_effect = _spawn_effect(spell)
		_cast_timer.start(spell.cast_time)
		return

	# Mana commits at cast start; the cooldown only starts when the cast
	# resolves — it's downtime after the spell, not overlapping the cast.
	player.mana -= spell.mana_cost
	GlobalEvent.player_mana_changed.emit(player.mana)

	if spell.cast_time > 0.0:
		player.fsm.transition_to("Cast")
		_cast_timer.start(spell.cast_time)
		_pending_spell = spell
		if spell.effect_at_cast_start:
			_spawn_effect(spell)
	else:
		_spawn_effect(spell)
		_start_cooldown(spell)

func _physics_process(delta: float) -> void:
	if _channel_spell == null:
		return
	_channel_drain += _channel_spell.mana_cost * delta
	var whole := int(_channel_drain)
	if whole > 0:
		_channel_drain -= whole
		player.mana = maxi(player.mana - whole, 0)
		GlobalEvent.player_mana_changed.emit(player.mana)
	if player.mana <= 0 or not Input.is_action_pressed(_channel_action):
		_end_channel()

func _end_channel() -> void:
	_cast_timer.stop()
	var spell := _channel_spell
	if is_instance_valid(_channel_effect):
		_channel_effect.channel_released()
	_channel_spell = null
	_channel_effect = null
	if not spell.channel_while_moving:
		player.fsm.transition_to("Idle")
	_start_cooldown(spell)

func _on_cast_time_finished() -> void:
	if _channel_spell:
		_end_channel()
		return
	var spell := _pending_spell
	_pending_spell = null
	player.fsm.transition_to("Idle")
	if spell:
		if not spell.effect_at_cast_start:
			_spawn_effect(spell)
		_start_cooldown(spell)

func _start_cooldown(spell: SpellResource) -> void:
	var cooldown: Timer = _cooldowns.get(spell)
	if not cooldown:
		cooldown = Timer.new()
		cooldown.one_shot = true
		add_child(cooldown)
		_cooldowns[spell] = cooldown
	cooldown.start(spell.cooldown)
	GlobalEvent.spell_cooldown_started.emit(spell, spell.cooldown)

func _spawn_effect(spell: SpellResource) -> Node:
	var effect = spell.effect_scene.instantiate()
	effect.setup(spell, player)
	get_tree().root.add_child(effect)
	return effect
