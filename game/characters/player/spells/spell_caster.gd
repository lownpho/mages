extends Node
class_name SpellCaster

## The cast engine, mounted on ANY caster (player, enemy, minion) as a child. It
## owns the generic flow — per-spell cooldowns, the cast_time wind-up, channels,
## and over-time effects that cool down when they finish — and spawns each effect
## through the setup(spell, host) contract, so the host (get_parent()) supplies
## stats, aim and faction. WHAT to cast and WHEN is a trigger's job:
## PlayerCastInput maps input + loadout to cast(); creature behaviours call cast()
## on their own timing. There is no "weapon" — everything is a spell, and any
## caster can cast any spell.

## A wind-up or channel began — the host may root itself / play a telegraph.
signal cast_started(spell)
## A wind-up finished and its effect spawned — the host may return to normal.
signal cast_resolved(spell)
## A channel ended (release, cap, or the host's own timing).
signal channel_ended(spell)

@onready var host: Node2D = get_parent()

var _cooldowns: Dictionary = {}  # SpellResource -> one-shot cooldown Timer
# SpellResource -> live over-time effect (one exposing "finished", e.g. a bullet-spell
# burst): the cooldown starts when it ends, and the spell can't recast while live.
var _await_finish: Dictionary = {}
var _cast_timer: Timer            # wind-up timer, doubling as the channel cap
var _pending_spell: SpellResource
var _channel_spell: SpellResource
var _channel_effect: Node

func _ready() -> void:
	_cast_timer = Timer.new()
	_cast_timer.one_shot = true
	_cast_timer.timeout.connect(_on_cast_time_finished)
	add_child(_cast_timer)

## Cast `spell` now if able. `aim` (non-zero) stamps the host's aim_direction for
## casters that aim by direction (creatures); the player leaves it zero and the
## effect samples the mouse. Returns true if the cast went off.
func cast(spell: SpellResource, aim: Vector2 = Vector2.ZERO) -> bool:
	if spell == null or spell.effect_scene == null:
		return false
	if not ready_for(spell) or not _host_ready():
		return false
	if aim != Vector2.ZERO and "aim_direction" in host:
		host.aim_direction = aim
	if spell.channeled:
		_begin_channel(spell)
	elif spell.cast_time > 0.0:
		_begin_windup(spell)
	else:
		# Instant: exclusivity (a second bullet spell cancelling the first) is handled by
		# the burst effect via host.register_burst, so instants stack cleanly here.
		_resolve_cooldown(spell, _spawn_effect(spell))
	return true

## True while `spell` is mid wind-up/channel or its over-time effect is still running.
## A behaviour waits on this to hold its state open for exactly one burst.
func is_casting(spell: SpellResource) -> bool:
	if _pending_spell == spell or _channel_spell == spell:
		return true
	var live = _await_finish.get(spell)
	return live != null and is_instance_valid(live)

## Cut `spell`'s live effect short — it goes on cooldown exactly as if it had run out.
## Lets a state that bails mid-burst (target out of range) take its shots with it.
func interrupt(spell: SpellResource) -> void:
	var live = _await_finish.get(spell)
	if live != null and is_instance_valid(live) and live.has_method("interrupt"):
		live.interrupt()

## Abandon `spell`'s wind-up before it resolves — the beat that started it bailed (target
## gone) — putting it on cooldown as if it had fired. Without this the caster would sit
## with a pending spell forever and refuse every later cast.
func cancel(spell: SpellResource) -> void:
	if _pending_spell != spell:
		return
	_pending_spell = null
	_cast_timer.stop()
	_start_cooldown(spell)

## True when `spell` is off cooldown and its last over-time effect has finished.
func ready_for(spell: SpellResource) -> bool:
	var cd: Timer = _cooldowns.get(spell)
	if cd and not cd.is_stopped():
		return false
	var live = _await_finish.get(spell)
	return live == null or not is_instance_valid(live)

# Busy mid wind-up/channel, or the host says it can't act (player mid-dash).
func _host_ready() -> bool:
	if _pending_spell != null or _channel_spell != null:
		return false
	return host.get("can_act") != false

func _begin_windup(spell: SpellResource) -> void:
	_cancel_bursts()
	_pending_spell = spell
	_cast_timer.start(spell.cast_time)
	cast_started.emit(spell)

func _begin_channel(spell: SpellResource) -> void:
	# The effect spawns at press (aim locks there); cast_time caps the channel.
	_cancel_bursts()
	_channel_spell = spell
	_channel_effect = _spawn_effect(spell)
	if spell.cast_time > 0.0:
		_cast_timer.start(spell.cast_time)
	cast_started.emit(spell)

## End a live channel — button release, the cast_time cap, or a behaviour's own
## timing all route here.
func end_channel() -> void:
	if _channel_spell == null:
		return
	_cast_timer.stop()
	var spell := _channel_spell
	if is_instance_valid(_channel_effect):
		_channel_effect.channel_released()
	_channel_spell = null
	_channel_effect = null
	_start_cooldown(spell)
	channel_ended.emit(spell)

func _on_cast_time_finished() -> void:
	if _channel_spell:
		end_channel()
		return
	var spell := _pending_spell
	_pending_spell = null
	if spell:
		_resolve_cooldown(spell, _spawn_effect(spell))
		cast_resolved.emit(spell)

# Interrupt any live burst on the host (player only) — exclusive spells cancel it.
func _cancel_bursts() -> void:
	if host.has_method("cancel_bursts"):
		host.cancel_bursts()

# An over-time effect (one exposing "finished") holds its spell live and cools
# down when it ends; anything else cools down immediately.
func _resolve_cooldown(spell: SpellResource, effect: Node) -> void:
	if effect.has_signal("finished"):
		_await_finish[spell] = effect
		effect.finished.connect(func() -> void:
			_await_finish.erase(spell)
			_start_cooldown(spell))
	else:
		_start_cooldown(spell)

func _start_cooldown(spell: SpellResource) -> void:
	var cd: Timer = _cooldowns.get(spell)
	if not cd:
		cd = Timer.new()
		cd.one_shot = true
		add_child(cd)
		_cooldowns[spell] = cd
	# Timer.start(0) keeps the previous wait_time instead of expiring at once, so a
	# zero-cooldown spell would inherit a phantom wait — just leave it stopped.
	if spell.cooldown <= 0.0:
		cd.stop()
		return
	cd.start(spell.cooldown)
	GlobalEvent.spell_cooldown_started.emit(spell, spell.cooldown)

func _spawn_effect(spell: SpellResource) -> Node:
	var effect = spell.effect_scene.instantiate()
	effect.setup(spell, host)
	get_tree().root.add_child(effect)
	return effect
