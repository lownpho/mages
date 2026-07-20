extends Node
## Headless bullet-spell burst test, driven through the real player scene and
## SpellCaster (this is machinery, not one spell's behaviour): a burst fires
## max_shots on cadence and the cooldown starts at burst END, not at cast;
## re-casting is blocked while the burst is live; starting an exclusive spell —
## a cast-time spell, a channel, or a second bullet spell — CANCELS the live burst
## onto its full cooldown (a single-shot instant bullet spell like zaap is a burst
## too, so it's exclusive as well). Slots live on two pages of two
## (cycle_spell_page flips which two the cast actions drive). Last subtest covers the
## burst's own shape — rotation_per_shot spiralling, aim_independent ignoring the
## caster — off a bare SpellCaster. Run:
##   godot --headless --path game res://tests/test_bullet_spell.tscn

const PLAYER_SCENE := preload("res://characters/player/player.tscn")

var fails: Array[String] = []
var player: CharacterBody2D
var caster: SpellCaster
var input: PlayerCastInput
var pew1: BulletSpellResource
var pew2: BulletSpellResource
var spawned: Dictionary = {}  # BulletResource -> bullets spawned carrying it
var directions: Array[Vector2] = []  # every spawned bullet's launch direction, in order

func _ready() -> void:
	get_tree().root.child_entered_tree.connect(_on_root_child)
	player = PLAYER_SCENE.instantiate()
	add_child(player)
	caster = player.get_node("SpellCaster")
	input = player.get_node("PlayerCastInput")
	pew1 = load("res://characters/player/spells/pew/pew1.tres")
	pew2 = load("res://characters/player/spells/pew/pew2.tres")
	# Page 0 holds the pews for every test; page 1 slot 0 is the swap slot each
	# cancel test loads with the spell it cancels *with* (four slots don't fit them
	# all at once), and page 1 slot 1 keeps nope.
	GlobalInventory.spell_slots.at(0).set_item(pew1)
	GlobalInventory.spell_slots.at(1).set_item(pew2)
	GlobalInventory.spell_slots.at(3).set_item(load("res://characters/player/spells/nope/nope.tres"))
	# Let the tree finish assembling before effects get added to the root.
	await get_tree().physics_frame
	await get_tree().physics_frame

	await _test_full_burst()
	await _test_cast_cancels_burst()
	await _test_bullet_cancels_bullet()
	await _test_instant_bullet_cancels_burst()
	await _test_channel_cancels_burst()
	await _test_burst_rotation()

	# Leave no equipment behind for a later scene run in the same session.
	for i in GlobalInventory.SPELL_SLOT_SIZE:
		GlobalInventory.spell_slots.at(i).clear_item()
	if GlobalInventory.active_spell_page != 0:
		GlobalInventory.cycle_spell_page()
	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)

func _on_root_child(node: Node) -> void:
	if node is BaseBullet:
		spawned[node.data] = spawned.get(node.data, 0) + 1
		directions.append(node.base_direction)

func _count(spell: BulletSpellResource) -> int:
	return spawned.get(spell.bullet, 0)

func _cooling(spell: SpellResource) -> bool:
	var t: Timer = caster._cooldowns.get(spell)
	return t != null and not t.is_stopped()

func _burst_live(spell: SpellResource) -> bool:
	var effect = caster._await_finish.get(spell)
	return effect != null and is_instance_valid(effect)

# Page 1, slot 0 — the shared slot each cancel test loads with its own spell.
func _equip_swap_slot(path: String) -> void:
	GlobalInventory.spell_slots.at(2).set_item(load(path))

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

# Cooldowns persist across subtests; wait one out so the next cast is clean.
func _wait_off_cooldown(spell: SpellResource) -> void:
	await _wait(spell.cooldown + 0.2)

func _test_full_burst() -> void:
	spawned.clear()
	input._try_cast(0)
	if not _burst_live(pew1):
		fails.append("burst effect not live right after cast")
	if _cooling(pew1):
		fails.append("cooldown started at cast — must start at burst end")
	input._try_cast(0)  # re-cast while live must be a no-op
	await _wait(pew1.shot_interval * pew1.max_shots + 0.3)
	if _count(pew1) != pew1.max_shots:
		fails.append("full burst spawned %d bullets, want %d" % [_count(pew1), pew1.max_shots])
	if not _cooling(pew1):
		fails.append("cooldown not running after the burst ended")
	if _burst_live(pew1):
		fails.append("burst effect still live after max_shots")
	await _wait_off_cooldown(pew1)

func _test_cast_cancels_burst() -> void:
	spawned.clear()
	_equip_swap_slot("res://characters/player/spells/fireball/fireball1.tres")
	input._try_cast(0)
	await _wait(0.6)  # ~3 of 6 shots at 0.25s cadence
	GlobalInventory.cycle_spell_page()
	input._try_cast(0)  # fireball: cast_time > 0, must cancel the burst
	GlobalInventory.cycle_spell_page()  # back to page 0
	var at_cancel := _count(pew1)
	if at_cancel == 0 or at_cancel >= pew1.max_shots:
		fails.append("unexpected shot count at cancel: %d" % at_cancel)
	if not _cooling(pew1):
		fails.append("cast-time spell did not put the live burst on cooldown")
	if _burst_live(pew1):
		fails.append("burst effect survived a cast-time spell")
	await _wait(0.7)  # fireball's 0.5s wind-up resolves, player is free again
	if _count(pew1) != at_cancel:
		fails.append("cancelled burst kept firing")
	await _wait_off_cooldown(pew1)

func _test_bullet_cancels_bullet() -> void:
	spawned.clear()
	input._try_cast(0)
	await _wait(0.3)  # ~2 pew1 shots
	input._try_cast(1)  # pew2: a second bullet spell cancels the first
	var p1 := _count(pew1)
	if not _cooling(pew1) or _burst_live(pew1):
		fails.append("second bullet spell did not cancel the first onto cooldown")
	await _wait(pew2.shot_interval * pew2.max_shots + 0.3)
	if _count(pew1) != p1:
		fails.append("cancelled bullet spell kept firing")
	if _count(pew2) != pew2.max_shots:
		fails.append("pew2 spawned %d bullets, want %d" % [_count(pew2), pew2.max_shots])
	if not _cooling(pew2):
		fails.append("pew2 not on cooldown after its burst")
	await _wait_off_cooldown(pew1)

func _test_instant_bullet_cancels_burst() -> void:
	spawned.clear()
	_equip_swap_slot("res://characters/player/spells/zaap/zaap1.tres")
	input._try_cast(0)
	await _wait(0.3)
	# Flip to page 1 mid-burst and cast zaap — a single-shot instant bullet spell
	# (cast_time 0, max_shots 1). It's still a burst, so it's exclusive: it cancels
	# the live pew burst onto cooldown like any other bullet spell.
	GlobalInventory.cycle_spell_page()
	var at_cancel := _count(pew1)
	input._try_cast(0)  # zaap (page 1, slot 0)
	if not _cooling(pew1) or _burst_live(pew1):
		fails.append("instant bullet spell did not cancel the live burst onto cooldown")
	await _wait(0.4)
	if _count(pew1) != at_cancel:
		fails.append("cancelled burst kept firing under an instant bullet spell")
	GlobalInventory.cycle_spell_page()  # back to page 0
	await _wait_off_cooldown(pew1)

func _test_channel_cancels_burst() -> void:
	spawned.clear()
	input._try_cast(0)
	await _wait(0.3)
	GlobalInventory.cycle_spell_page()
	input._try_cast(1)  # nope (page 1, slot 1): channeled, cancels at press
	var at_cancel := _count(pew1)
	if not _cooling(pew1) or _burst_live(pew1):
		fails.append("channel did not cancel the live burst onto cooldown")
	# Headless has no held button, so the channel releases next frame.
	await _wait(0.5)
	if _count(pew1) != at_cancel:
		fails.append("channel-cancelled burst kept firing")
	GlobalInventory.cycle_spell_page()  # back to page 0
	await _wait_off_cooldown(pew1)

# The burst-shaping dials that used to live on the RotatingVolley behaviour: a spell
# with rotation_per_shot spirals its own aim shot to shot, and aim_independent ignores
# the caster entirely so the spray paints the arena from its own bearing. Cast off a
# bare SpellCaster — the point is that the spell carries the shape, not the caster.
func _test_burst_rotation() -> void:
	var rig := Node2D.new()
	rig.set_script(load("res://tests/support/stub_caster.gd"))
	add_child(rig)
	var rig_caster := SpellCaster.new()
	rig.add_child(rig_caster)
	await get_tree().physics_frame

	var spell: BulletSpellResource = load(
		"res://characters/enemies/fae/fae_rings_spell.tres")
	directions.clear()
	rig_caster.cast(spell, Vector2.RIGHT)
	await _wait(spell.shot_interval * spell.max_shots + 0.3)

	var ring: int = spell.fire_pattern.num_bullets
	if directions.size() != ring * spell.max_shots:
		fails.append("ring burst spawned %d bullets, want %d" % [
			directions.size(), ring * spell.max_shots])
		rig.queue_free()
		return
	# Compare the first bullet of consecutive pulses: each is rotation_per_shot on.
	for shot in spell.max_shots - 1:
		var drift := _deg_between(directions[shot * ring], directions[(shot + 1) * ring])
		if absf(drift - spell.rotation_per_shot) > 0.5:
			fails.append("pulse %d drifted %.1f deg, want %.1f" % [
				shot, drift, spell.rotation_per_shot])
			break
	# aim_independent: the burst must NOT sit on the aim we handed cast().
	if absf(_deg_between(Vector2.RIGHT, directions[0])) < 0.5:
		fails.append("aim_independent burst fired along the caster's aim")
	rig.queue_free()

func _deg_between(from: Vector2, to: Vector2) -> float:
	return rad_to_deg(from.angle_to(to))
