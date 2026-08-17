extends CharacterBody2D
class_name Creature

## A faction-agnostic AI combatant (FSM + hurtbox + caster + targeting), shared by the
## hostile enemy roster and the player's summoned minions. Hostiles author a `data`
## resource and drops; summons leave `data` null and have their stats injected by the
## summon spawner before they enter the tree (see summon_spawner).
@export var data: CreatureResource

## Groups this creature hunts. Default is the player plus any summons, so enemies
## split aggro onto the player's minions for free. A summon flips this to the
## "enemies" group — the targeting code below is faction-agnostic.
@export var target_groups: Array[String] = ["player", "summon"]
## Physics layer the caster stamps on bullets it fires. Enemies fire enemy bullets;
## a summon overrides this to player bullets so its shots hit enemy hurtboxes.
@export var bullet_collision_layer: int = GameConstants.LAYER_ENEMY_BULLETS
## FSM state entered INSTEAD of dying, when health runs out — a parting shot, a split, a
## detonation. The creature is freed the moment that beat hands off to anything else, so a
## death throe is an ordinary Behaviour (a Cast, a Hold) rather than bespoke death code.
## Empty = die immediately, which is what every ordinary creature wants.
@export var death_state: String = ""

# Mirrored from `data` at _ready (when present) so behaviours can read
# creature.max_health directly and damage can mutate health. Summons inject
# max_health instead of carrying a `data` resource.
## Only read by a body with NO `data`: a bloatcap's mycelings are its spawn rather than a
## roster entry, so they carry no stat sheet (no icon, no drops, no kill count) and author
## their health here instead. `data` wins wherever it's set.
@export var max_health: int = 1
var drops: Array[LootDrop] = []
var health: int

# Creature damage never scales with a stat — it's authored flat on each spell's
# bullet — but spell effects read caster.skill/speed/defence through the shared
# contract, and a summoned minion is a Creature stamped with the player's stats so
# its bullet scales exactly as if the player cast it (see summon_spawner).
var skill: int = 0
var speed: int = 0
var defence: int = 0
# Where this creature's spells aim, stamped by SpellCaster.cast() from
# the behaviour's chosen target point; effects sample it via get_aim_direction()
# (the same call they make on the player).
var aim_direction: Vector2 = Vector2.RIGHT

# Multiplier applied to incoming damage in _on_hurt. A behaviour that armours the
# creature for a beat (e.g. rosebud's Guard reload pose) drops this below 1.0 in
# enter() and restores it to 1.0 in exit(); left at 1.0 it's a no-op for everyone else.
# Zero (or less) is the one special case: flat immunity rather than a 1-damage floor, so a
# beat that takes the creature out of the fight entirely — the mole underground, a boss
# invulnerable until its adds clear — is the same dial turned all the way down.
var incoming_damage_scale: float = 1.0

## True while this creature is being driven by a dash rather than by its FSM state, so a
## caster spell (ChargeDash) can move ANY host. False the rest of the time; the player
## carries the same flag, which is what makes the spell faction-agnostic.
var can_act: bool = true
## A dash ended against a wall head-on rather than running its course — the razorback's
## stun window. Only the slam fires it; a dash that simply expires does not.
signal dash_blocked

## Live absorb effect soaking incoming damage before it reaches health — the same hook
## the player carries, so a shield spell is faction-agnostic like every other: a moss
## golem casting Nope on itself runs the player's own bubble effect unmodified. The
## effect registers itself here in setup() and clears it when its channel ends.
var damage_absorber: Node2D = null

# Set once by die(); guards against the death re-running while queue_free is pending.
var _dead: bool = false
# Set when health ran out and the death beat took over — the creature is walking dead until
# that beat hands off. Guards the throe against re-entering on a hit that lands during it.
var _dying: bool = false

# Dash drive (see start_dash), mirroring the player's: while the clock runs, _dash_velocity
# overrides whatever the FSM state wanted.
var _dash_velocity: Vector2 = Vector2.ZERO
var _dash_until_ms: int = 0
# How square a wall hit has to be to count as a head-on slam rather than a graze.
const DASH_SLAM_DOT := -0.5

# Decaying knockback impulse (px/s), applied on top of whatever the FSM state
# does each physics frame. A spell pushes the creature by calling apply_knockback;
# it bleeds off at KNOCKBACK_DECAY so the shove is a brief slide, not teleportation.
var _knockback: Vector2 = Vector2.ZERO
const KNOCKBACK_DECAY := 1200.0

# Off-screen sleep margin: the area (centred on the creature) that must touch the screen
# for it to stay awake. 8 tiles each side so a creature wakes well before it scrolls into
# view rather than popping into motion at the edge.
const SLEEP_MARGIN := 8 * GameConstants.PX_PER_TILE
const SLEEP_RECT := Rect2(-SLEEP_MARGIN, -SLEEP_MARGIN, 2 * SLEEP_MARGIN, 2 * SLEEP_MARGIN)

# Telegraph flash: how long the single pulse holds, and the palette-safe flattener the UI
# already uses for its icon flashes.
const TELEGRAPH_FLASH := 0.12
const _FLATTEN := preload("res://gui/flatten.gdshader")
var _telegraph_tween: Tween

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox = $Hurtbox
@onready var fsm: FSM = $FSM

func _ready() -> void:
	if data:
		max_health = data.max_health
		drops = data.drops
	health = max_health
	hurtbox.hurt.connect(_on_hurt)
	# Sleep while off-screen: disable the whole creature (AI, physics, timers, hurtbox)
	# when it leaves the screen and wake it when it returns, so a large world only ticks
	# the creatures the player can see. The notifier's visibility check runs in the server,
	# not in _process, so a process-disabled creature still wakes itself back up.
	var enabler := VisibleOnScreenEnabler2D.new()
	enabler.rect = SLEEP_RECT
	add_child(enabler)
	# RayCast2D defaults hit_from_inside to false, so a probe whose origin sits inside the
	# target's own collider (the player standing on/overlapping this creature) reports no
	# hit at all — the creature goes blind at melee range. Force every LOS probe on so
	# adjacency never breaks targeting.
	for child in get_children():
		if child is RayCast2D:
			child.hit_from_inside = true
	# Deferred: the freshly instantiated tree is still blocked during _ready, so
	# behaviours can't parent their timers yet. Deferred calls flush FIFO and the
	# behaviours' _ready run before ours, so every timer exists before start().
	fsm.start.call_deferred()

# Push this creature with a velocity impulse (px/s) that decays to zero. Generic
# and faction-agnostic — any radial-push spell (Thwomp) reuses it by capability.
func apply_knockback(impulse: Vector2) -> void:
	_knockback += impulse

## Drive this creature in a straight line at `dash_speed` for `duration`, overriding its
## FSM state's movement — the capability ChargeDash calls on its caster, which the player
## also exposes. The heading is locked here: the spell aims it once, and nothing steers it
## after, which is exactly what makes a charge dodgeable.
func start_dash(direction: Vector2, dash_speed: float, duration: float) -> void:
	_dash_velocity = direction.normalized() * dash_speed
	_dash_until_ms = Time.get_ticks_msec() + int(duration * 1000.0)
	can_act = false

func is_dashing() -> bool:
	return Time.get_ticks_msec() < _dash_until_ms

## Health has run out and the death beat is playing. Anything that would redirect the FSM
## on an outside event has to sit this out, or the throe is over before it starts — the
## killing blow reaches a hit-alert beat through the SAME hurtbox emission that started it.
func is_dying() -> bool:
	return _dying

func _physics_process(delta: float) -> void:
	if _dash_until_ms > 0:
		_drive_dash()
	if _knockback == Vector2.ZERO:
		return
	move_and_collide(_knockback * delta)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)

func _drive_dash() -> void:
	if not is_dashing():
		_end_dash()
		return
	velocity = _dash_velocity
	move_and_slide()
	if _slammed():
		_end_dash()
		dash_blocked.emit()

# A wall the dash ran into square-on, not one it scraped past — a charger that clips a trunk
# at a shallow angle should keep going rather than stun itself on the scenery.
func _slammed() -> bool:
	var heading := _dash_velocity.normalized()
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_normal().dot(heading) <= DASH_SLAM_DOT:
			return true
	return false

func _end_dash() -> void:
	_dash_velocity = Vector2.ZERO
	_dash_until_ms = 0
	velocity = Vector2.ZERO
	can_act = true

func make_timer(on_timeout: Callable) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.timeout.connect(on_timeout)
	add_child.call_deferred(timer)  # deferred for the same reason as fsm.start()
	return timer

# Nearest node across target_groups — the thing this character should attack.
func get_target() -> Node2D:
	var nearest: Node2D = null
	var best := INF
	for group in target_groups:
		for node in get_tree().get_nodes_in_group(group):
			var dist: float = global_position.distance_squared_to(node.global_position)
			if dist < best:
				best = dist
				nearest = node
	return nearest

func get_aim_direction() -> Vector2:
	return aim_direction

func probe_sees(probe: RayCast2D) -> bool:
	var collider = probe.get_collider()
	if collider == null:
		return false
	for group in target_groups:
		if collider.is_in_group(group):
			return true
	return false

func look_for_target(probe: RayCast2D) -> bool:
	var target = get_target()
	if not target:
		return false
	probe.look_at(target.global_position)
	# RayCast2D only recasts once per physics step; without forcing an update here,
	# probe_sees would read the collision from *before* this frame's look_at, which is
	# harmless for callers polling every physics frame (the lag self-corrects) but wrong
	# for a one-shot check like Guard's post-windup decision.
	probe.force_raycast_update()
	return probe_sees(probe)

## Pulse the whole sprite once in a flat colour at the moment a creature commits to a beat.
## The wind-up already exists mechanically (Cast holds it for the spell's cast_time); this
## is what makes the player SEE it — one flash in the creature's own accent, so the tell
## says both "incoming" and "from what", then the sprite is itself again for the rest of
## the wind-up. ONE pulse, deliberately: a repeating blink over a two-second channel reads
## as a strobe, and the animation is already carrying the wind-up.
## Flat, never a blend: the shader can't put an off-palette colour on screen.
func telegraph(color: Color) -> void:
	telegraph_off()
	var mat := ShaderMaterial.new()
	mat.shader = _FLATTEN
	mat.set_shader_parameter("flat_color", Color(color.r, color.g, color.b, 1.0))
	# The swap is the material itself, not the shader's alpha — flatten MULTIPLIES the
	# texture's alpha, so dialling flat_color.a to 0 would blink the creature out of
	# existence rather than back to its own colours.
	sprite.material = mat
	_telegraph_tween = create_tween()
	_telegraph_tween.tween_interval(TELEGRAPH_FLASH)
	_telegraph_tween.tween_callback(_set_flash.bind(null))

func _set_flash(mat: ShaderMaterial) -> void:
	sprite.material = mat

func telegraph_off() -> void:
	if _telegraph_tween:
		_telegraph_tween.kill()
		_telegraph_tween = null
	sprite.material = null

func play(anim: String, speed_scale: float = 1.0) -> void:
	# A summon may lack an animation a behaviour asks for (e.g. a static turret with no
	# idle tag). Rather than error on the missing anim, lock in place on the current frame.
	sprite.speed_scale = speed_scale
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
	else:
		sprite.pause()

## Play `anim` so its strike (final) frame lands exactly `duration` seconds in. A wind-up
## is the spell's own cast_time, so the tell is stretched or squeezed to fit rather than
## hoping the authored frame rate happens to agree — retuning cast_time restyles the
## telegraph instead of desyncing it, and the same spell cast by a creature with different
## frames still reads correctly. A looping pose has no strike frame to land, so it just
## runs at its authored speed for however long the wind-up lasts.
func play_fitted(anim: String, duration: float) -> void:
	var frames := sprite.sprite_frames
	if duration <= 0.0 or frames == null or not frames.has_animation(anim) \
			or frames.get_animation_loop(anim):
		play(anim)
		return
	var count := frames.get_frame_count(anim)
	var fps := frames.get_animation_speed(anim)
	if count <= 1 or fps <= 0.0:
		play(anim)
		return
	# Frames carry per-frame duration multipliers, so the strike frame appears once every
	# earlier frame has had its turn — not simply at (count-1)/fps.
	var until_strike := 0.0
	for i in count - 1:
		until_strike += frames.get_frame_duration(anim, i)
	play(anim, (until_strike / fps) / duration)

func face(dir_x: float) -> void:
	# Deadzone ignores near-vertical headings so the sprite doesn't flip-flicker.
	if absf(dir_x) > 0.01:
		sprite.flip_h = dir_x < 0.0

func die() -> void:
	# queue_free() only lands at end of frame, so hits queued in the same physics step
	# (pellets, a bullet plus its blast) would re-enter here and double-count the death.
	if _dead or _dying:
		return
	if death_state != "" and fsm.states.has(death_state):
		_begin_death_throe()
		return
	_finish_death()

# Hand the FSM one last beat before the creature is gone. It's immune for the duration
# (nothing should be able to cut a parting shot short), and the first hand-off OUT of that
# beat is the real death — so the throe's own done_state/next_state terminates it and no
# sentinel state has to exist for the state-name lint to find.
func _begin_death_throe() -> void:
	_dying = true
	fsm.transition_to(death_state)
	# Connected AFTER the transition: transition_to emits synchronously, so hooking up first
	# would fire on our own entry and kill the creature before the beat ran a frame. Handing
	# off is all a dispatcher does, so a Gate's pick is the throe STARTING, not ending — that
	# is what lets a parting shot be a choice (the Mycelium's broods answer coated floor with
	# a bigger ring). _finish_death is idempotent, so this needs no one-shot.
	fsm.state_changed.connect(func(previous: State, _current: State) -> void:
		if not (previous is Gate):
			_finish_death())

func _finish_death() -> void:
	if _dead:
		return
	_dead = true
	if data:
		GlobalEvent.creature_died.emit(data, global_position)
		for spawn in data.death_spawns:
			spawn.spawn(get_parent(), global_position)
	for drop in drops:
		if drop.roll():
			GlobalEvent.loot_dropped.emit(drop.item, global_position)
	queue_free()

func _on_hurt(damage: int, source: Node) -> void:
	# Already out of the fight: a creature mid death-throe is immune, so nothing can cut its
	# parting shot short (and health can't run out twice).
	if _dead or _dying:
		return
	# A shield eats the hit before armour or health see it, matching the player's order.
	if damage_absorber and is_instance_valid(damage_absorber):
		damage = damage_absorber.absorb(damage)
		if damage <= 0:
			return
	if incoming_damage_scale <= 0.0:
		return
	if incoming_damage_scale != 1.0:
		damage = maxi(1, int(ceil(damage * incoming_damage_scale)))
	# Floored at zero: health is read as a FRACTION of max by every beat's health window, and
	# an overkill that leaves it negative puts the creature below `health_min` on windows that
	# start at 0 — so a death throe pointed at an ordinary state finds nothing eligible to hand
	# off to and the corpse lies there playing its last frame forever.
	health = maxi(health - damage, 0)
	# Emit before die() frees us so the floating number still spawns on a live node.
	GlobalEvent.entity_damaged.emit(self, damage, source)
	if health <= 0:
		die()
