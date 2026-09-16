class_name ContentLoader
extends RefCounted
## The content load pass. It finds every file of a content folder, loads it and checks the model,
## collecting every problem with its file and line into the WorldContent it returns:
##
##   world.tres                          the Ideal path and Side biomes (WorldResource)
##   challenge_curve.tres                the global Challenge settings (ChallengeCurveResource)
##   biomes/<biome>/biome.tres           a Biome (BiomeResource)
##   biomes/<biome>/zones/<zone>.tres    one of its Zones (ZoneResource)
##
## Folder and file names are the ids. They are found with ResourceLoader.list_directory, which also
## lists an export's remapped files, so nothing registers content by hand.
##
## One pass reports every kind of problem:
##   - parse errors and missing references, as the engine reports them while loading;
##   - properties a section sets that its script doesn't declare, which a load drops silently;
##   - numbers outside their property's export range;
##   - model rules: topology, the Spawn zone, Bosses, Entry challenges, Sign reveals, Zone
##     quotas and Side-biome attachments.
## A model rule is skipped when a file it reads failed to load, so a broken file doesn't bury the
## report under problems it caused.

const WORLD_FILE := "world.tres"
const CURVE_FILE := "challenge_curve.tres"
const BIOME_FILE := "biome.tres"

var _content := WorldContent.new()
## Load files from disk again rather than from the resource cache.
var _reread := false
## File path -> its text layout, for line numbers.
var _indexes: Dictionary[String, TresIndex] = {}
var _reported: Dictionary[String, bool] = {}
## Some file failed to load, so rules that read the whole World are skipped.
var _incomplete := false
## Biome id -> how many Zone files its zones/ folder holds, loaded or not.
var _zone_files: Dictionary[StringName, int] = {}
var _missing_reference := RegEx.create_from_string("referenced non-existent resource at: (.+?)\\.?$")


## reread loads the content files again from disk instead of reusing cached resources, as the
## debug reload does after they were edited.
static func load_content(root: String, reread := false) -> WorldContent:
	var loader := ContentLoader.new()
	loader._reread = reread
	loader._run(root)
	return loader._content


## Keeps the engine's text-resource parse errors ("res://a.tres:8 - Parse Error: ...") while a
## load runs.
class EngineErrors extends Logger:
	var errors: Array[ContentError] = []
	var _pattern := RegEx.create_from_string("^(.+?):(\\d+) - (.+)$")
	var _mutex := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, code: String, _rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var found := _pattern.search(code)
		if found == null:
			return
		_mutex.lock()
		errors.append(ContentError.new(found.get_string(1), found.get_string(2).to_int(), found.get_string(3)))
		_mutex.unlock()


func _run(root: String) -> void:
	_content.root = root.trim_suffix("/") + "/"
	var engine := EngineErrors.new()
	OS.add_logger(engine)
	_load_files()
	OS.remove_logger(engine)
	for error in engine.errors:
		# A file that exists but failed to load reports its own problem; files referencing it only
		# echo it.
		var missing := _missing_reference.search(error.message)
		if missing == null or not ResourceLoader.exists(missing.get_string(1)):
			_add(error.file, error.line, error.message)
	_check_model()
	_content.errors.sort_custom(func(a: ContentError, b: ContentError) -> bool:
		if a.file != b.file:
			return a.file < b.file
		if a.line != b.line:
			return a.line < b.line
		return a.message < b.message)


# --- Finding and loading ---------------------------------------------------------------------------


func _load_files() -> void:
	var root := _content.root
	_content.curve = _load(root + CURVE_FILE, ChallengeCurveResource) as ChallengeCurveResource
	var biome_ids := _entries(root + "biomes/", "/")
	if biome_ids.is_empty():
		_add(root + "biomes/", 0, "no Biome folders")
	for id in biome_ids:
		var dir := root + "biomes/" + id + "/"
		var biome := _load(dir + BIOME_FILE, BiomeResource) as BiomeResource
		if biome != null:
			_content.biomes[StringName(id)] = biome
		var files := _entries(dir + "zones/", ".tres")
		_zone_files[StringName(id)] = files.size()
		if files.is_empty():
			_add(dir + "zones/", 0, "Biome '%s' has no Zone files" % id)
		var zones: Dictionary[StringName, ZoneResource] = {}
		for file in files:
			var zone := _load(dir + "zones/" + file, ZoneResource) as ZoneResource
			if zone != null:
				zones[StringName(file.get_basename())] = zone
		_content.zones[StringName(id)] = zones
	# Last, so the Biomes it references are already loaded and cached.
	_content.world = _load(root + WORLD_FILE, WorldResource) as WorldResource


## The sorted names in dir ending with suffix: "/" lists folders (named without the slash).
func _entries(dir: String, suffix: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for entry in ResourceLoader.list_directory(dir):
		if entry.ends_with(suffix) and not entry.begins_with("."):
			out.append(entry.trim_suffix("/"))
	out.sort()
	return out


func _load(path: String, type: Script) -> Resource:
	if not ResourceLoader.exists(path):
		_add(path, 0, "missing: expected a %s" % type.get_global_name())
		_incomplete = true
		return null
	var resource := ResourceLoader.load(path, "",
			ResourceLoader.CACHE_MODE_REPLACE if _reread else ResourceLoader.CACHE_MODE_REUSE)
	_index(path)
	if resource == null:
		_incomplete = true
		return null
	if not is_instance_of(resource, type):
		var script := resource.get_script() as Script
		var actual: String = String(script.get_global_name()) if script != null else resource.get_class()
		_error_at(resource, "script", "is a %s, not a %s" % [actual, type.get_global_name()])
		_incomplete = true
		return null
	_check_ranges(resource)
	return resource


## Reads a file's text for line numbers and reports the properties its sections' scripts don't
## declare. An export has no text to read, so it goes without both.
func _index(path: String) -> void:
	if _indexes.has(path):
		return
	var index := TresIndex.read(path)
	if index == null:
		return
	_indexes[path] = index
	for unknown in index.unknown_properties():
		_add(path, unknown.line, "'%s' is not a property of %s" % [unknown.name, String(unknown.script).get_file()])


# --- Reporting ------------------------------------------------------------------------------------


func _add(file: String, line: int, message: String) -> void:
	var key := "%s:%d:%s" % [file, line, message]
	if not _reported.has(key):
		_reported[key] = true
		_content.errors.append(ContentError.new(file, line, message))


## Reports a problem at a resource's property, or at one entry of a dictionary property.
func _error_at(resource: Resource, property: String, message: String, key: Variant = null) -> void:
	var file := resource.resource_path
	var section := ""
	if file.contains("::"):
		section = file.get_slice("::", 1)
		file = file.get_slice("::", 0)
	var index: TresIndex = _indexes.get(file)
	_add(file, 0 if index == null else index.line_of(section, property, key), message)


## An enemy's id: its data sheet's folder name.
func _name(creature: Resource) -> String:
	return creature.resource_path.get_base_dir().get_file()


func _number(value: float) -> String:
	return str(int(value)) if value == floorf(value) else str(value)


# --- Rules ----------------------------------------------------------------------------------------


func _check_model() -> void:
	if _content.curve != null:
		_check_curve(_content.curve)
	for creature in _creatures():
		_index(creature.resource_path)
		_check_ranges(creature)
		if creature.group_max < creature.group_min:
			_error_at(creature, "group_max", "group_max %d is below group_min %d" % [creature.group_max, creature.group_min])
	if _content.world != null:
		_check_topology()
	for id in _content.biomes:
		_check_biome(id)
	if _incomplete or _content.world == null:
		return
	_check_spawn_zone()
	_check_reveals()
	_check_attachments()


## Every int or float exported with a range lies inside it. The inspector clamps; a text edit doesn't.
func _check_ranges(resource: Resource) -> void:
	for property in (resource.get_script() as Script).get_script_property_list():
		if property.hint != PROPERTY_HINT_RANGE or not (property.type in [TYPE_INT, TYPE_FLOAT]):
			continue
		var hint := String(property.hint_string)
		var bounds := hint.split(",")
		var value: float = resource.get(property.name)
		var low := bounds[0].to_float()
		var high := bounds[1].to_float()
		if value < low and not hint.contains("or_less"):
			_error_at(resource, property.name, "%s is %s, below its minimum %s" % [property.name, _number(value), _number(low)])
		elif value > high and not hint.contains("or_greater"):
			_error_at(resource, property.name, "%s is %s, above its maximum %s" % [property.name, _number(value), _number(high)])


func _check_curve(curve: ChallengeCurveResource) -> void:
	for property in ["encounters_per_tile", "types_per_encounter"]:
		var steps: Dictionary = curve.get(property)
		if not steps.has(0):
			_error_at(curve, property, "%s needs a step at Challenge 0" % property)
		for challenge: int in steps:
			var value: float = steps[challenge]
			if challenge < 0:
				_error_at(curve, property, "%s has a step at Challenge %d, below 0" % [property, challenge], challenge)
			if property == "types_per_encounter" and value < 1:
				_error_at(curve, property, "types_per_encounter at Challenge %d is %s, below 1" % [challenge, _number(value)], challenge)
			elif value < 0:
				_error_at(curve, property, "encounters_per_tile at Challenge %d is %s, below 0" % [challenge, _number(value)], challenge)


func _check_topology() -> void:
	var world := _content.world
	var placed: Dictionary[StringName, bool] = {}
	if world.ideal_path.is_empty():
		_error_at(world, "ideal_path", "the Ideal path is empty")
	for biome in world.ideal_path:
		var id := _biome_id(biome)
		if id == &"":
			_error_at(world, "ideal_path", "the Ideal path names %s, which is not a Biome folder in %sbiomes/" % [_describe(biome), _content.root])
		elif placed.has(id):
			_error_at(world, "ideal_path", "Biome '%s' appears in the topology more than once" % id)
		else:
			placed[id] = true
			_content.ideal_path.append(id)
	for side in world.side_biomes:
		if side == null:
			_error_at(world, "side_biomes", "side_biomes has an empty record")
			continue
		var id := _biome_id(side.biome)
		var parent := _biome_id(side.parent)
		if id == &"":
			_error_at(side, "biome", "a Side biome record names %s, which is not a Biome folder in %sbiomes/" % [_describe(side.biome), _content.root])
		elif placed.has(id):
			_error_at(side, "biome", "Biome '%s' appears in the topology more than once" % id)
		elif not _content.ideal_path.has(parent):
			placed[id] = true
			_error_at(side, "parent", "Side biome '%s' has parent %s, which is not on the Ideal path" % [id, _describe(side.parent) if parent == &"" else "'%s'" % parent])
		else:
			placed[id] = true
			_content.parents[id] = parent
	for id in _content.biomes:
		if not placed.has(id):
			_error_at(world, "ideal_path", "Biome '%s' is neither on the Ideal path nor a Side biome" % id)


## A Biome's id when it is a loaded biome.tres of this content folder, otherwise &"".
func _biome_id(biome: BiomeResource) -> StringName:
	if biome == null:
		return &""
	var prefix := _content.root + "biomes/"
	var path := biome.resource_path
	if not path.begins_with(prefix) or not path.ends_with("/" + BIOME_FILE):
		return &""
	var id := StringName(path.trim_prefix(prefix).trim_suffix("/" + BIOME_FILE))
	return id if _content.biomes.get(id) == biome else &""


func _describe(resource: Resource) -> String:
	return "nothing" if resource == null else resource.resource_path


func _check_biome(id: StringName) -> void:
	var biome := _content.biomes[id]
	var placed := _content.ideal_path.has(id) or _content.parents.has(id)
	var low := _content.lowest_challenge(id) if placed else -1
	if _content.parents.has(id):
		var parent := _content.parents[id]
		var parent_exit := _content.biomes[parent].exit_challenge
		if biome.exit_challenge < parent_exit:
			_error_at(biome, "exit_challenge", "exit_challenge %d is below the %d its parent '%s' exits at" % [biome.exit_challenge, parent_exit, parent])
	elif placed and biome.exit_challenge <= low:
		_error_at(biome, "exit_challenge", "exit_challenge %d doesn't rise above the %d Biome '%s' starts at" % [biome.exit_challenge, low, id])
	_check_roster(biome, {}, low, biome.exit_challenge)
	if biome.presentation == null:
		_error_at(biome, "presentation", "Biome '%s' has no presentation" % id)
	if biome.boss == null:
		_error_at(biome, "boss", "Biome '%s' has no Boss" % id)
	else:
		_check_encounter(biome.boss, "the Boss")
	_check_objects(biome)
	var zones: Dictionary = _content.zones[id]
	var all_zones_loaded := zones.size() == _zone_files[id]
	for zone_id: StringName in zones:
		var zone: ZoneResource = zones[zone_id]
		_check_roster(zone, biome.roster, low, biome.exit_challenge)
		for list in ["minibosses", "rares"]:
			for encounter: FixedEncounterResource in zone.get(list):
				if encounter == null:
					_error_at(zone, list, "%s has an empty entry" % list)
				else:
					_check_encounter(encounter, "a Miniboss" if list == "minibosses" else "a Rare")
		_check_objects(zone)
		if zone.decoration_density < 0.0 and zone.decoration_density != -1.0:
			_error_at(zone, "decoration_density", "decoration_density is %s: use -1 to keep the Biome's, or 0 to 1" % _number(zone.decoration_density))
		if zone.spawn and placed and _content.ideal_path.find(id) != 0:
			_error_at(zone, "spawn", "the Spawn zone must belong to the Ideal path's first Biome, not '%s'" % id)
		if all_zones_loaded:
			_check_capacity(zone, zones.size())


## An owner is a Biome or a Zone. A Zone adds to its Biome's shared roster and may not repeat it.
## low < 0 skips Entry challenge ranges, for a Biome the topology doesn't place.
func _check_roster(owner: Resource, shared: Dictionary, low: int, high: int) -> void:
	var roster: Dictionary = owner.get("roster")
	for enemy: CreatureResource in roster:
		if enemy == null:
			_error_at(owner, "roster", "a roster entry names no enemy")
			continue
		var entry: int = roster[enemy]
		if shared.has(enemy):
			_error_at(owner, "roster", "%s is already on the Biome's shared roster" % _name(enemy), enemy)
		if low >= 0 and (entry < low or entry > high):
			_error_at(owner, "roster", "%s enters at Challenge %d, outside the Biome's %d to %d" % [_name(enemy), entry, low, high], enemy)
	_check_duplicate_keys(owner, "roster")


func _check_encounter(encounter: FixedEncounterResource, role: String) -> void:
	if encounter.leader == null:
		_error_at(encounter, "leader", "%s has no leader" % role)
	for escort: CreatureResource in encounter.escorts:
		if escort == null:
			_error_at(encounter, "escorts", "an escort of %s names no enemy" % role)
		elif encounter.escorts[escort] < 1:
			_error_at(encounter, "escorts", "%s escorts %d %s; use at least 1" % [role.capitalize(), encounter.escorts[escort], _name(escort)], escort)
	_check_duplicate_keys(encounter, "escorts")


## Signs and Breather Objects of a Biome or Zone. Sign reveals need every Boss, so they wait for
## _check_reveals.
func _check_objects(owner: Resource) -> void:
	for sign_resource: SignResource in owner.get("signs"):
		if sign_resource == null:
			_error_at(owner, "signs", "signs has an empty entry")
		elif sign_resource.text.strip_edges().is_empty():
			_error_at(sign_resource, "text", "a Sign has no text")
	var objects: Dictionary = owner.get("breather_objects")
	for scene: PackedScene in objects:
		if scene == null:
			_error_at(owner, "breather_objects", "a Breather Object names no scene")
		elif objects[scene] < 1:
			_error_at(owner, "breather_objects", "Breather Object %s has weight %d; use at least 1" % [scene.resource_path.get_file(), objects[scene]], scene)
	_check_duplicate_keys(owner, "breather_objects")


## A dictionary naming one file under two ext ids silently keeps a single entry.
func _check_duplicate_keys(resource: Resource, property: String) -> void:
	var file := resource.resource_path.get_slice("::", 0)
	var index: TresIndex = _indexes.get(file)
	if index == null:
		return
	var section := resource.resource_path.get_slice("::", 1) if resource.resource_path.contains("::") else ""
	var seen: Dictionary[String, bool] = {}
	for entry: Dictionary in index.entries(section, property):
		if seen.has(entry.key):
			_add(file, entry.line, "%s lists %s twice" % [property, String(entry.key).get_file()])
		seen[entry.key] = true


## room_count must hold the route Rooms and every set piece the Zone may need. Seeded ordering can
## place any Zone but the Spawn zone last in its Biome, where it also holds the Biome's Boss.
func _check_capacity(zone: ZoneResource, biome_zones: int) -> void:
	var may_hold_boss := not zone.spawn or biome_zones == 1
	var needed := zone.route_rooms + zone.minibosses.size() + zone.rares.size() + (1 if may_hold_boss else 0)
	if zone.room_count >= needed:
		return
	var parts: Array[String] = ["%d route Rooms" % zone.route_rooms]
	if not zone.minibosses.is_empty():
		parts.append("%d Minibosses" % zone.minibosses.size())
	if not zone.rares.is_empty():
		parts.append("%d Rares" % zone.rares.size())
	if may_hold_boss:
		parts.append("the Boss" if biome_zones == 1 else "a possible Boss")
	var listed := ", ".join(parts.slice(0, -1)) + " and " + parts[-1] if parts.size() > 1 else parts[0]
	_error_at(zone, "room_count", "room_count %d cannot hold %s (needs %d)" % [zone.room_count, listed, needed])


func _check_spawn_zone() -> void:
	var spawns: Array[String] = []
	for biome_id in _content.zones:
		for zone_id: StringName in _content.zones[biome_id]:
			if (_content.zones[biome_id][zone_id] as ZoneResource).spawn:
				spawns.append("%s/%s" % [biome_id, zone_id])
	if spawns.size() == 1:
		_content.spawn_zone = spawns[0]
	elif spawns.is_empty():
		_error_at(_content.world, "ideal_path", "no Zone is the Spawn zone: set spawn = true on one Zone of the first Biome")
	else:
		for key in spawns:
			var zone: ZoneResource = _content.zones[StringName(key.get_slice("/", 0))][StringName(key.get_slice("/", 1))]
			_error_at(zone, "spawn", "%d Zones are the Spawn zone (%s); keep exactly one" % [spawns.size(), ", ".join(spawns)])


## A Sign reveals the nearest Boss or Miniboss its enemy leads, so that enemy must lead one of them.
func _check_reveals() -> void:
	var leaders: Dictionary[String, bool] = {}
	var encounters: Array[FixedEncounterResource] = []
	for biome in _content.biomes.values():
		encounters.append(biome.boss)
	for zones: Dictionary in _content.zones.values():
		for zone: ZoneResource in zones.values():
			encounters.append_array(zone.minibosses)
	for encounter in encounters:
		if encounter != null and encounter.leader != null:
			leaders[encounter.leader.resource_path] = true
	for owner in _owners():
		for sign_resource: SignResource in owner.get("signs"):
			if sign_resource != null and sign_resource.reveals != null and not leaders.has(sign_resource.reveals.resource_path):
				_error_at(sign_resource, "reveals", "a Sign reveals %s, which leads no Boss or Miniboss" % _name(sign_resource.reveals))


## Each parent needs distinct route Rooms for its Side biomes, spaced apart and away from its ends.
func _check_attachments() -> void:
	var children: Dictionary[StringName, int] = {}
	for side in _content.parents:
		children[_content.parents[side]] = children.get(_content.parents[side], 0) + 1
	for parent in children:
		var count := children[parent]
		var needed := 2 * WorldContent.ATTACHMENT_MARGIN + (count - 1) * WorldContent.ATTACHMENT_SPACING + 1
		var route := _content.route_rooms(parent)
		if route < needed:
			_error_at(_content.world, "side_biomes", "'%s' has %d route Rooms, too few to attach %d Side biomes %d apart and %d from either end (needs %d)" % [
					parent, route, count, WorldContent.ATTACHMENT_SPACING, WorldContent.ATTACHMENT_MARGIN, needed])


## Every loaded Biome, then every loaded Zone.
func _owners() -> Array[Resource]:
	var out: Array[Resource] = []
	out.append_array(_content.biomes.values())
	for zones: Dictionary in _content.zones.values():
		out.append_array(zones.values())
	return out


## Every enemy data sheet the content references, once each.
func _creatures() -> Array[CreatureResource]:
	var found: Dictionary[String, CreatureResource] = {}
	var add := func(creature: CreatureResource) -> void:
		if creature != null and creature.resource_path.ends_with(".tres"):
			found[creature.resource_path] = creature
	var encounters: Array[FixedEncounterResource] = []
	for owner in _owners():
		for enemy: CreatureResource in owner.get("roster"):
			add.call(enemy)
		for sign_resource: SignResource in owner.get("signs"):
			if sign_resource != null:
				add.call(sign_resource.reveals)
		if owner is BiomeResource:
			encounters.append(owner.boss)
		else:
			encounters.append_array(owner.minibosses)
			encounters.append_array(owner.rares)
	for encounter in encounters:
		if encounter != null:
			add.call(encounter.leader)
			for escort: CreatureResource in encounter.escorts:
				add.call(escort)
	return found.values()
