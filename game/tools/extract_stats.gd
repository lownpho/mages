extends Node

## Balance-sheet extractor. Walks every stat-bearing .tres in the project, reads
## the typed @export values off the loaded resource (no text parsing), and writes
## one JSON file: entries grouped by category, each with its stats inline.
##
## Run headless:
##   godot --headless --path game tools/extract_stats.tscn
## Output: ../docs/balance/stats.json (sibling of the Godot project root).

const SCAN_ROOTS := ["res://characters", "res://items"]
const OUT_REL := "../docs/balance/stats.json"

func _ready() -> void:
	var sheet := {}  # category -> Array[entry]

	var files := PackedStringArray()
	for root in SCAN_ROOTS:
		_collect_tres(root, files)
	files.sort()

	var count := 0
	for path in files:
		var res = ResourceLoader.load(path)
		if res == null:
			continue
		var category := _classify(res)
		if category == "":
			continue  # registries, themes, sub-resources we don't sheet
		var base := path.get_file().get_basename()
		if category == "enemy":
			base = base.trim_suffix("_data")  # snake_data.tres -> snake
		var name_tier := _split_tier(base)
		var entry := {"name": name_tier[0]}
		if name_tier[1] != "":
			entry["tier"] = int(name_tier[1])
		entry["stats"] = _stats(res)
		if not sheet.has(category):
			sheet[category] = []
		sheet[category].append(entry)
		count += 1

	_write_json(sheet)
	print("extract_stats: wrote %d resources across %d categories -> %s" % [count, sheet.size(), OUT_REL])
	get_tree().quit()

func _collect_tres(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect_tres(full, out)
		elif entry.ends_with(".tres"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()

# Most specific class first: every equippable is a spell now.
func _classify(res: Resource) -> String:
	if res is CreatureResource: return "enemy"
	if res is SpellResource: return "spell"
	if res is BulletResource: return "bullet"
	if res is ItemResource: return "item"
	return ""

# Trailing digits are the tier (zaap1 -> zaap, 1; snake_weapon -> snake_weapon, "").
func _split_tier(base: String) -> Array:
	var i := base.length()
	while i > 0 and base[i - 1] >= "0" and base[i - 1] <= "9":
		i -= 1
	if i == base.length():
		return [base, ""]
	return [base.substr(0, i), base.substr(i)]

func _stats(res: Resource) -> Dictionary:
	var stats := {}
	_add_numeric(res, stats, "")

	# Weapon spells embed their bullet — flatten its stats and a derived DPS
	# (full burst damage over one burst+cooldown cycle, pattern multiplier in).
	if res is WeaponSpellResource and res.bullet != null:
		_add_numeric(res.bullet, stats, "bullet_")
		var cycle: float = res.shot_interval * res.max_shots + res.cooldown
		if cycle > 0.0:
			stats["dps_derived"] = res.bullet.base_damage * _pattern_count(res.fire_pattern) \
					* res.max_shots / cycle
	elif res is SpellResource and res.base_damage > 0.0 and res.cooldown > 0.0:
		stats["dps_derived"] = res.base_damage / res.cooldown
	return stats

# Bullets per trigger pull for a fire pattern (shotgun pellets, ring bullets, 1 otherwise).
func _pattern_count(pattern: FirePattern) -> int:
	if pattern == null:
		return 1
	if "num_pellets" in pattern:
		return pattern.num_pellets
	if "num_bullets" in pattern:
		return pattern.num_bullets
	return 1

# Only the script's own exported int/float/bool vars — skips inherited Resource
# bookkeeping, group headers, and texture/scene/array references.
func _add_numeric(res: Resource, out: Dictionary, prefix: String) -> void:
	for prop in res.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if not (prop.usage & PROPERTY_USAGE_STORAGE):
			continue
		var t: int = prop.type
		if t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_BOOL:
			out[prefix + prop.name] = res.get(prop.name)

func _write_json(sheet: Dictionary) -> void:
	var out_path := ProjectSettings.globalize_path("res://").path_join(OUT_REL)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("extract_stats: cannot open %s" % out_path)
		return
	f.store_string(JSON.stringify(sheet, "\t"))
	f.close()
