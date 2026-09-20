extends Node
class_name PlayerCastInput

## The player's trigger for the SpellCaster engine, and the only player-specific piece of
## casting: cast1..cast4 = LMB/MMB/RMB/SPACE (L1/L2/R1/R2 on pad) fire the matching slot of
## GlobalInventory's spell row. What's in that row is what the mage can cast; changing it
## means moving a spell there from the bag, in the HUD.

const SPELL_ACTIONS = ["cast1", "cast2", "cast3", "cast4"]

@onready var player: CharacterBody2D = get_parent()
@onready var caster: SpellCaster = get_parent().get_node("SpellCaster")

# The action holding an active channel, polled for release; "" when not channeling.
var _channel_action: String = ""

# Action indices held down since a press this node actually saw, re-tried every physics
# frame so a held key casts again the moment the spell leaves cooldown. Armed at press
# rather than polled blind, so a click the HUD swallowed can't start a repeat.
var _repeating: Dictionary = {}

func _ready() -> void:
	caster.cast_started.connect(func(_spell: SpellResource) -> void:
		player.fsm.transition_to("Cast"))
	caster.cast_resolved.connect(func(_spell: SpellResource) -> void:
		player.fsm.transition_to("Idle"))
	caster.channel_ended.connect(func(_spell: SpellResource) -> void:
		_channel_action = ""
		player.fsm.transition_to("Idle"))

func _unhandled_input(event: InputEvent) -> void:
	# HUD slot navigation owns the pad while captured — triggers/bumpers must not
	# fire casts under the player's feet.
	if GlobalInput.ui_captured:
		return
	# fresh_press, not is_action_pressed: the cast actions sit on analog triggers, which
	# report the action pressed on every step of the pull.
	for i in SPELL_ACTIONS.size():
		if GlobalInput.fresh_press(event, SPELL_ACTIONS[i]):
			_repeating[i] = true
			_try_cast(i)
			return

func _try_cast(action_index: int) -> void:
	var slot := GlobalInventory.spell_slot(action_index)
	if slot == null or slot.item == null:
		return
	var spell := slot.item as SpellResource
	if spell == null:
		return
	# Aim comes from the mouse (the effect samples get_aim_direction), so no aim
	# is passed here — the engine only stamps a direction for creature casters.
	if caster.cast(spell) and spell.channeled:
		_channel_action = SPELL_ACTIONS[action_index]

# Hold-to-channel: release (or the engine's cap, via channel_ended) ends it.
# Hold-to-repeat: a still-held cast action re-casts as soon as cast() will take it —
# every guard (cooldown, live burst, mid wind-up, can_act) lives in there, so retrying
# every frame is free and the spell goes off the instant it's ready.
func _physics_process(_delta: float) -> void:
	if _channel_action != "" and not Input.is_action_pressed(_channel_action):
		caster.end_channel()
	for i: int in _repeating.keys():
		if not Input.is_action_pressed(SPELL_ACTIONS[i]):
			_repeating.erase(i)
		elif not GlobalInput.ui_captured:
			_try_cast(i)
