extends Node
class_name PlayerCastInput

## The player's trigger for the SpellCaster engine, and the only player-specific piece of
## casting: cast1..cast4 = LMB/MMB/RMB/SPACE (L1/L2/R1/R2 on pad) fire the matching slot on
## GlobalInventory's active line; switch_line (SHIFT or pad Y) cycles which line that is.
##
## Switching is not free — it plants the mage in the Cast state for SWITCH_TIME and drops
## whatever was in flight, so a line swap is a commitment mid-fight rather than a free
## eight-spell bar.

const SPELL_ACTIONS = ["cast1", "cast2", "cast3", "cast4"]
const SWITCH_TIME := 0.5

@onready var player: CharacterBody2D = get_parent()
@onready var caster: SpellCaster = get_parent().get_node("SpellCaster")

# The action holding an active channel, polled for release; "" when not channeling.
var _channel_action: String = ""
# Seconds left in a line switch; the line flips when it reaches zero.
var _switch_left: float = 0.0

func _ready() -> void:
	caster.cast_started.connect(func(_spell: SpellResource) -> void:
		player.fsm.transition_to("Cast"))
	caster.cast_resolved.connect(func(_spell: SpellResource) -> void:
		player.fsm.transition_to("Idle"))
	caster.channel_ended.connect(func(_spell: SpellResource) -> void:
		_channel_action = ""
		# A switch aborts the channel on its way in; the root owns the FSM from there.
		if _switch_left <= 0.0:
			player.fsm.transition_to("Idle"))

func _unhandled_input(event: InputEvent) -> void:
	# HUD slot navigation owns the pad while captured — triggers/bumpers must not
	# fire casts or flip lines under the player's feet.
	if GlobalInput.ui_captured or _switch_left > 0.0:
		return
	# fresh_press, not is_action_pressed: the cast actions sit on analog triggers, which
	# report the action pressed on every step of the pull.
	if GlobalInput.fresh_press(event, &"switch_line"):
		_start_switch()
		return
	for i in SPELL_ACTIONS.size():
		if GlobalInput.fresh_press(event, SPELL_ACTIONS[i]):
			_try_cast(i)
			return

func _try_cast(action_index: int) -> void:
	var slot := GlobalInventory.active_slot(action_index)
	if slot == null or slot.item == null:
		return
	var spell := slot.item as SpellResource
	if spell == null:
		return
	# Aim comes from the mouse (the effect samples get_aim_direction), so no aim
	# is passed here — the engine only stamps a direction for creature casters.
	if caster.cast(spell) and spell.channeled:
		_channel_action = SPELL_ACTIONS[action_index]

# Plant the mage and start the clock. Anything mid-flight ends here, onto its full
# cooldown — the same exclusivity a new cast has always imposed on a live burst.
func _start_switch() -> void:
	caster.abort()
	_channel_action = ""
	_switch_left = SWITCH_TIME
	player.fsm.transition_to("Cast")

# Hold-to-channel: release (or the engine's cap, via channel_ended) ends it.
func _physics_process(delta: float) -> void:
	if _switch_left > 0.0:
		_switch_left -= delta
		if _switch_left <= 0.0:
			GlobalInventory.cycle_line()
			player.fsm.transition_to("Idle")
		return
	if _channel_action != "" and not Input.is_action_pressed(_channel_action):
		caster.end_channel()
