extends Behaviour
class_name FireWhenInRange

## Hysteresis margin (px) the exit probe reaches past the attack probe. Attack is entered
## on the short attack probe (Chase's call) but only left once the player clears this
## longer exit probe, so a player slower than the enemy can't sit on the attack boundary
## and strobe Chase <-> Attack. Derived per-enemy from its own attack probe, so the whole
## roster gets the deadband without a second probe node in every scene.
const EXIT_MARGIN := 8.0

@export var weapon_path: NodePath
@export var weapon_data: SpellResource
@export var attack_probe_path: NodePath
@export var out_of_range_state: String = "Chase"
## The wind-up-to-strike animation played per shot when `animation_driven`; the pose held
## while firing on the legacy path. Defaults to the idle pose for enemies with no attack anim.
@export var attack_anim: String = "idle"

## When true (the default) each shot is telegraphed: the creature waits in `idle_anim`, and
## only when the weapon is off cooldown does it play `attack_anim` as a wind-up, firing when
## the sprite reaches `release_frame`, then drops back to idle. So the animation always
## precedes and triggers the shot and the player gets reaction time; the rest between shots is
## the spell's `cooldown`. Works whether `attack_anim` loops or not (it plays a single
## pass per shot either way). Set false for the legacy fire-every-cooldown-frame behaviour.
@export var animation_driven: bool = true
## Frame of `attack_anim` the shot leaves on. -1 = the last frame. Keep it > 0 so the wind-up
## reads before the strike. Ignored unless `animation_driven`.
@export var release_frame: int = -1
## Resting pose shown between telegraphed shots. Ignored unless `animation_driven`.
@export var idle_anim: String = "idle"

@onready var _weapon: CreatureSpellCaster = get_node(weapon_path)
@onready var _probe: RayCast2D = get_node(attack_probe_path)
var _exit_probe: RayCast2D
# animation_driven bookkeeping: whether an attack anim is mid-play, and whether this pass has
# already released its shot (so the wrap/finish only fires once and only returns to idle after).
var _winding_up: bool = false
var _fired: bool = false

func _ready() -> void:
	super()
	if weapon_data:
		_weapon.setup_for_creature(weapon_data)
	# Child of the attack probe so it inherits the per-frame look_at aim for free; only its
	# length differs.
	_exit_probe = RayCast2D.new()
	_exit_probe.collision_mask = _probe.collision_mask
	_exit_probe.target_position = Vector2(_probe.target_position.length() + EXIT_MARGIN, 0)
	_exit_probe.hit_from_inside = true
	_exit_probe.enabled = false
	_probe.add_child(_exit_probe)

func enter() -> void:
	_probe.enabled = true
	_exit_probe.enabled = true
	if animation_driven:
		# Rest in idle; physics_update kicks off a wind-up once the weapon is ready. The
		# sprite's own frames then drive the shot (release frame) and the return to idle
		# (animation_finished — attack anims are authored non-looping).
		_winding_up = false
		_fired = false
		creature.play(idle_anim)
		creature.sprite.frame_changed.connect(_on_frame_changed)
		creature.sprite.animation_finished.connect(_on_animation_finished)
	else:
		creature.play(attack_anim)

func exit() -> void:
	_probe.enabled = false
	_exit_probe.enabled = false
	if creature.sprite.frame_changed.is_connected(_on_frame_changed):
		creature.sprite.frame_changed.disconnect(_on_frame_changed)
	if creature.sprite.animation_finished.is_connected(_on_animation_finished):
		creature.sprite.animation_finished.disconnect(_on_animation_finished)

func physics_update(_delta: float) -> void:
	var player := creature.get_target()
	if not player:
		creature.fsm.transition_to(out_of_range_state)
		return

	_probe.look_at(player.global_position)
	creature.face(player.global_position.x - creature.global_position.x)

	# Leave only when the player clears the longer exit probe; the gap between the two probes
	# is the hysteresis deadband.
	if not creature.probe_sees(_exit_probe):
		creature.fsm.transition_to(out_of_range_state)
		return
	if not creature.probe_sees(_probe):
		return

	if animation_driven:
		# Kick off a telegraphed shot when idle and the weapon has come off cooldown. Once a
		# wind-up is running we're committed — the frame handlers finish it.
		if not _winding_up and _weapon.can_cast:
			_winding_up = true
			_fired = false
			creature.play(attack_anim)
	else:
		_fire(player)

# Override point: subclasses that need to alter the fired direction (e.g. a rotating ring)
# hook in here instead of duplicating physics_update. Reached from both the legacy per-frame
# path and the animation-driven release frame.
func _fire(player: Node2D) -> void:
	_weapon.try_cast(creature.global_position, player.global_position)

# The wind-up's strike frame: release the shot once, committed regardless of current aim (we
# already decided to attack when the wind-up began).
func _on_frame_changed() -> void:
	if not _winding_up or _fired:
		return
	if creature.sprite.animation != attack_anim or creature.sprite.frame != _resolved_release_frame():
		return
	_fired = true
	var player := creature.get_target()
	if player:
		_fire(player)

# Wind-up finished (attack anims are non-looping, so this always fires): drop back to the
# resting pose. The weapon's cooldown gates the next wind-up in physics_update.
func _on_animation_finished() -> void:
	if creature.sprite.animation == attack_anim:
		_winding_up = false
		creature.play(idle_anim)

func _resolved_release_frame() -> int:
	if release_frame >= 0:
		return release_frame
	var frames := creature.sprite.sprite_frames
	if frames and frames.has_animation(attack_anim):
		return maxi(0, frames.get_frame_count(attack_anim) - 1)
	return 0
