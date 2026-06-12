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
	if player.mana < spell.mana_cost:
		return

	# Mana and cooldown commit at cast start — a cast time is a commitment.
	player.mana -= spell.mana_cost
	GlobalEvent.player_mana_changed.emit(player.mana)
	if not cooldown:
		cooldown = Timer.new()
		cooldown.one_shot = true
		add_child(cooldown)
		_cooldowns[spell] = cooldown
	cooldown.start(spell.cooldown)
	GlobalEvent.spell_cooldown_started.emit(spell, spell.cooldown)

	if spell.cast_time > 0.0:
		player.fsm.transition_to("Cast")
		_cast_timer.start(spell.cast_time)
		if spell.effect_at_cast_start:
			_spawn_effect(spell)
		else:
			_pending_spell = spell
	else:
		_spawn_effect(spell)

func _on_cast_time_finished() -> void:
	var spell := _pending_spell
	_pending_spell = null
	player.fsm.transition_to("Idle")
	if spell:
		_spawn_effect(spell)

func _spawn_effect(spell: SpellResource) -> void:
	var effect = spell.effect_scene.instantiate()
	effect.setup(spell, player)
	get_tree().root.add_child(effect)
