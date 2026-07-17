extends Node
class_name SpellCaster

## Casts the spells equipped on GlobalInventory's active spell page. The generic
## flow lives here — input (cast1/cast2/cast3 = LMB/RMB/Space; cycle_page = SHIFT
## flips the page), per-spell cooldowns, and the cast-time root (the player FSM's
## "Cast" state). Everything spell-specific lives in the spell's effect scene,
## spawned through the setup(spell, caster) contract (see SpellResource).

const SPELL_ACTIONS = ["cast1", "cast2", "cast3"]

@onready var player: CharacterBody2D = get_parent()

var _cooldowns: Dictionary = {}  # SpellResource -> one-shot cooldown Timer
# SpellResource -> live effect that runs over time (it has a "finished" signal,
# e.g. a weapon burst): the cooldown starts when the effect ends, not at spawn,
# and the spell can't be re-cast while its effect is live.
var _await_finish: Dictionary = {}
var _cast_timer: Timer
var _pending_spell: SpellResource
# Shing: when armed, the NEXT spell's effect spawns a second time (a delayed
# echo). Arming is deferred so the spell that arms it (Shing) never echoes itself.
var _echo_active: bool = false
const _ECHO_DELAY := 0.18
var _channel_spell: SpellResource
var _channel_effect: Node
var _channel_action: String

func _ready() -> void:
	_cast_timer = Timer.new()
	_cast_timer.one_shot = true
	_cast_timer.timeout.connect(_on_cast_time_finished)
	add_child(_cast_timer)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_page"):
		GlobalInventory.cycle_spell_page()
		return
	for i in SPELL_ACTIONS.size():
		if event.is_action_pressed(SPELL_ACTIONS[i]):
			_try_cast(i)
			return

func _try_cast(action_index: int) -> void:
	var slot := GlobalInventory.active_spell_slot(action_index)
	if slot == null or slot.item == null:
		return
	var spell := slot.item as SpellResource
	if spell == null or spell.effect_scene == null:
		return
	# Cooldowns are keyed by the spell itself, not the slot, so moving a spell
	# to another slot or page mid-cooldown can't dodge it. Tiers are distinct spells.
	var cooldown: Timer = _cooldowns.get(spell)
	if cooldown and not cooldown.is_stopped():
		return
	var live = _await_finish.get(spell)
	if live != null and is_instance_valid(live):
		return
	# can_use_weapon doubles as "free to act": false while mid-cast.
	if not player.can_use_weapon:
		return
	# A moving channel doesn't enter the Cast state, so can_use_weapon can't
	# block a second cast mid-channel — gate explicitly: one channel at a time.
	if _channel_spell != null:
		return

	if spell.channeled:
		# Channeled: the effect spawns at press (aim locks there); cast_time is
		# the channel cap (0 = uncapped).
		player.cancel_bursts()
		if not spell.channel_while_moving:
			player.fsm.transition_to("Cast")
		_channel_spell = spell
		_channel_action = SPELL_ACTIONS[action_index]
		_channel_effect = _spawn_effect(spell)
		if spell.cast_time > 0.0:
			_cast_timer.start(spell.cast_time)
		return

	if spell.cast_time > 0.0:
		player.cancel_bursts()
		player.fsm.transition_to("Cast")
		_cast_timer.start(spell.cast_time)
		_pending_spell = spell
		if spell.effect_at_cast_start:
			_spawn_effect(spell)
	else:
		_resolve_cooldown(spell, _spawn_effect(spell))

func _physics_process(_delta: float) -> void:
	if _channel_spell == null:
		return
	if not Input.is_action_pressed(_channel_action):
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
		if spell.effect_at_cast_start:
			_start_cooldown(spell)
		else:
			_resolve_cooldown(spell, _spawn_effect(spell))

# Cooldown for a freshly spawned effect: an over-time effect (one exposing a
# "finished" signal) holds its spell live and starts the cooldown when it ends;
# anything else cools down immediately.
func _resolve_cooldown(spell: SpellResource, effect: Node) -> void:
	if effect.has_signal("finished"):
		_await_finish[spell] = effect
		effect.finished.connect(func() -> void:
			_await_finish.erase(spell)
			_start_cooldown(spell))
	else:
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
	# Consume a pending Shing echo: re-spawn this spell's effect once, shortly
	# after. The echo spawn re-enters here with _echo_active already false, so it
	# never chains. Weapon-spell bursts are the one caveat — a second burst
	# cancels the first — but nukes (Shing's intended target) echo cleanly.
	if _echo_active:
		_echo_active = false
		_schedule_echo(spell)
	return effect

func _schedule_echo(spell: SpellResource) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = _ECHO_DELAY
	add_child(timer)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(player):
			_spawn_effect(spell)
		timer.queue_free())
	timer.start()

# Called by Shing's effect. Deferred activation means the arming cast (Shing
# itself) has already spawned its own effect before the echo goes live, so Shing
# never doubles itself — the very next spell does.
func arm_echo() -> void:
	set_deferred("_echo_active", true)
