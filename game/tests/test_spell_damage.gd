extends Node
## Guards how a spell's damage reaches its bullets: a spell is self-contained (its own
## pattern, bullet and damage), the damage lives on the spell rather than the bullet, and
## the caster stamps it onto every shot. A spell that lost its damage in a copy deals 0
## silently — nothing else in the suite would catch that.
##   godot --headless --path game res://tests/test_spell_damage.tscn

# Distinct non-zero stats so a dropped term (skill vs speed vs defence) shows up.
const SKILL := 7
const SPEED := 11
const DEFENCE := 5

var _fails: Array[String] = []

func _ready() -> void:
	var caster := _make_caster()
	add_child(caster)
	await get_tree().physics_frame

	var checked := 0
	for path in _spell_paths():
		var res: Resource = load(path)
		if res == null:
			continue
		checked += _check(res, path.get_file().get_basename(), caster)

	print("spell damage: %d casts checked" % checked)
	if _fails.is_empty():
		print("ALL PASS")
	else:
		for f in _fails:
			print("  FAIL: ", f)
		print("FAILED: %d" % _fails.size())
	get_tree().quit()

func _check(res: Resource, label: String, caster: Node2D) -> int:
	var checked := 0
	if res is BulletSpellResource and res.bullet != null:
		checked += 1
		# Each spell owns its bullet outright: a standalone resource_path would mean two
		# spells share one instance, so retuning an enemy would silently retune a tier.
		var owner: String = res.bullet.resource_path
		if not owner.is_empty() and not owner.contains("::"):
			_fails.append("%s shares an external bullet (%s)" % [label, owner])
		if res.damage == null:
			_fails.append("%s has no damage" % label)
		else:
			var ctx := CastContext.new(res, caster)
			var bullet: BaseBullet = ctx.spawn_bullet(res.bullet, Vector2.RIGHT, Vector2.ZERO)
			var expected: int = res.damage.compute(SKILL, SPEED, DEFENCE)
			var actual: int = bullet.computed_damage()
			if actual != expected:
				_fails.append("%s: bullet deals %d, spell says %d" % [label, actual, expected])
			if expected <= 0:
				_fails.append("%s computes no damage at all" % label)
			bullet.queue_free()
	if res is SummonResource and res.minion_spell != null:
		checked += _check(res.minion_spell, label + ":minion", caster)
	return checked

# Minimal stand-in for a caster: CastContext reads position, aim and stats off it.
func _make_caster() -> Node2D:
	var node := Node2D.new()
	node.set_script(preload("res://tests/support/stub_caster.gd"))
	node.skill = SKILL
	node.speed = SPEED
	node.defence = DEFENCE
	return node

func _spell_paths() -> PackedStringArray:
	var out: PackedStringArray = []
	for root in ["res://characters/player/spells", "res://characters/enemies"]:
		var dir: DirAccess = DirAccess.open(root)
		if dir == null:
			continue
		for sub in dir.get_directories():
			var folder: String = root + "/" + sub
			var inner: DirAccess = DirAccess.open(folder)
			if inner == null:
				continue
			for file in inner.get_files():
				if file.ends_with(".tres") and not file.ends_with("_data.tres"):
					out.append(folder + "/" + file)
	return out
