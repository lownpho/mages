extends Node
class_name PlayerCastInput

## The player's trigger for the SpellCaster engine, and the only player-specific piece of
## casting: cast1/cast2/cast3 = LMB/RMB/MMB fire the matching slot on GlobalInventory's
## active page; cycle_page (SPACE or the wheel) flips the page — the wheel only reaches
## here when the cursor isn't over a map, which consumes it for zoom.

const SPELL_ACTIONS = ["cast1", "cast2", "cast3"]

@onready var player: CharacterBody2D = get_parent()
@onready var caster: SpellCaster = get_parent().get_node("SpellCaster")

# The action holding an active channel, polled for release; "" when not channeling.
var _channel_action: String = ""

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
	# fire casts or flip pages under the player's feet.
	if GlobalInput.ui_captured:
		return
	# fresh_press, not is_action_pressed: cycle_page sits on an analog trigger, which reports
	# the action pressed on every step of the pull. Page flips have no cooldown to hide that.
	if GlobalInput.fresh_press(event, &"cycle_page"):
		# One flip per physical notch — a web burst would otherwise land on the wrong
		# page, and the next middle-click casts that page's spell. SPACE/pad are exempt.
		if event is InputEventMouseButton and not GlobalInput.wheel_fresh:
			return
		GlobalInventory.cycle_spell_page()
		return
	for i in SPELL_ACTIONS.size():
		if GlobalInput.fresh_press(event, SPELL_ACTIONS[i]):
			_try_cast(i)
			return

func _try_cast(action_index: int) -> void:
	var slot := GlobalInventory.active_spell_slot(action_index)
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
func _physics_process(_delta: float) -> void:
	if _channel_action != "" and not Input.is_action_pressed(_channel_action):
		caster.end_channel()
