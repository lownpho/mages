extends Control
## Debug-only minimap overlay (scenes/debug_world.tscn ONLY — never world.tscn). Read-only: each
## redraw samples the live MacroMap on a coarse tile grid centred on the FlyCam and paints biomes,
## area tints, trail tiles, special/centre markers and the player. Press R to reroll the world
## (streamer.reseed(randi())). Sampling is coarse + throttled so it stays cheap; it never mutates
## the world. No class_name (preloaded via the scene) to avoid a global-class-cache rebuild.

const _SAMPLES := 60            # grid cells per axis
const _TILES_PER_SAMPLE := 32   # world tiles between samples → window ≈ 1920 tiles across (~1.3 biomes)
const _MAP_PX := 80.0           # on-screen map size (px) — must fit the 320×180 viewport
const _REDRAW_HZ := 8.0
const _TRAIL_SUBSTEP := 6       # trail probe step in tiles; ≤ 2*Trails.HALF_WIDTH catches every corridor
const _TRAIL_COLOR := Color(0.95, 0.85, 0.45)

const _SPECIAL_COLORS := {
	&"portal": Color(0.30, 0.80, 1.00),
	&"door": Color(0.90, 0.55, 0.20),
	&"sign": Color(1.00, 0.90, 0.30),
	&"coverage": Color(0.40, 1.00, 0.50),
	&"rare": Color(1.00, 0.40, 0.90),
	&"boss": Color(1.00, 0.25, 0.25),
}

@export var streamer_path: NodePath
@export var player_path: NodePath

@onready var _info: Label = $Info

var _streamer: ChunkStreamer
var _player: Node2D
var _cell := _MAP_PX / _SAMPLES
var _accum := 0.0
var _shown_seed := 9223372036854775807   # force the label to sync once init has set the real seed


func _ready() -> void:
	_streamer = get_node_or_null(streamer_path) as ChunkStreamer
	_player = get_node_or_null(player_path) as Node2D


func _process(dt: float) -> void:
	if _streamer and _streamer.current_seed() != _shown_seed:
		_shown_seed = _streamer.current_seed()
		_info.text = "seed %d   [R] reroll" % _shown_seed
	_accum += dt
	if _accum >= 1.0 / _REDRAW_HZ:
		_accum = 0.0
		queue_redraw()


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_R and _streamer:
		_streamer.reseed(randi())   # _process picks up the new seed for the label next frame
		queue_redraw()


func _draw() -> void:
	if not _streamer or not _player:
		return
	var macro := _streamer.macro()
	if macro == null:
		return   # init not done yet (world.gd calls it after our _ready)

	var pt := Vector2i((_player.global_position / GameConstants.PX_PER_TILE).round())
	var origin := Vector2(_MAP_PX, _MAP_PX) * 0.5
	draw_rect(Rect2(Vector2.ZERO, Vector2(_MAP_PX, _MAP_PX)), Color(0, 0, 0, 0.6))   # off-world reads black

	# Biome fill, tinted by area type, overridden where a trail is sampled.
	@warning_ignore("integer_division")
	var half := _SAMPLES / 2
	for j in _SAMPLES:
		for i in _SAMPLES:
			var tile := pt + Vector2i(i - half, j - half) * _TILES_PER_SAMPLE
			var biome := macro.biome_at(tile)
			if biome == null:
				continue
			var col := _biome_color(biome)
			var area := macro.area_at(tile)
			if area != null:
				col = col.lerp(_area_shade(area), 0.30)
			if _cell_has_trail(macro, tile):
				col = _TRAIL_COLOR
			draw_rect(Rect2(i * _cell, j * _cell, _cell + 1.0, _cell + 1.0), col)

	# Specials (portals/doors/signs/coverage/rares/bosses) → small coloured dots.
	for s in macro.specials():
		var p := _to_local(s.tile, pt, origin)
		if _in_map(p):
			draw_circle(p, 1.8, _SPECIAL_COLORS.get(s.type, Color.WHITE))

	# Biome centres → white rings.
	var centers: Dictionary = macro.biome_centers()
	for node in centers:
		var p: Vector2 = _to_local(centers[node], pt, origin)
		if _in_map(p):
			draw_arc(p, 2.5, 0.0, TAU, 12, Color.WHITE, 1.0)

	# Player (always map centre) → filled dot with dark ring.
	draw_arc(origin, 3.0, 0.0, TAU, 14, Color.BLACK, 1.5)
	draw_circle(origin, 1.5, Color.WHITE)

	draw_rect(Rect2(Vector2.ZERO, Vector2(_MAP_PX, _MAP_PX)), Color(1, 1, 1, 0.5), false, 1.0)
	_draw_legend()


# Legend glyphs mirror the shapes drawn on the map: dot = special marker, square = trail
# fill, ring = biome centre, and the player dot — so each on-map mark reads back to a name.
func _draw_legend() -> void:
	var font := ThemeDB.fallback_font
	var y := _MAP_PX + 5.0
	var rows := [
		["portal", _SPECIAL_COLORS[&"portal"], "dot"],
		["dungeon door", _SPECIAL_COLORS[&"door"], "dot"],
		["sign", _SPECIAL_COLORS[&"sign"], "dot"],
		["coverage spot", _SPECIAL_COLORS[&"coverage"], "dot"],
		["rare enemy", _SPECIAL_COLORS[&"rare"], "dot"],
		["boss", _SPECIAL_COLORS[&"boss"], "dot"],
		["trail", _TRAIL_COLOR, "square"],
		["biome centre", Color.WHITE, "ring"],
		["you", Color.WHITE, "player"],
	]
	for r in rows:
		var c := Vector2(4.0, y + 3.0)
		match r[2]:
			"dot": draw_circle(c, 2.0, r[1])
			"square": draw_rect(Rect2(1.0, y, 6.0, 6.0), r[1])
			"ring": draw_arc(c, 3.0, 0.0, TAU, 10, r[1], 1.0)
			"player":
				draw_arc(c, 3.0, 0.0, TAU, 10, Color.BLACK, 1.5)
				draw_circle(c, 1.5, Color.WHITE)
		draw_string(font, Vector2(11.0, y + 6.0), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
		y += 9.0


# A corridor is only ~7 tiles wide but samples sit 32 tiles apart, so an exact-point is_trail
# nearly always misses — trails flickered as stray dots. Instead ask whether a trail crosses the
# cell's footprint by probing a sub-grid at _TRAIL_SUBSTEP (≤ 2*Trails.HALF_WIDTH, so a corridor
# can't slip between probes); a hit paints the whole cell, drawing trails as continuous lines.
# Off-corridor probes hit an empty is_trail bucket and reject in O(1), so cost stays near the rails.
func _cell_has_trail(macro: Object, center: Vector2i) -> bool:
	@warning_ignore("integer_division")
	var r := _TILES_PER_SAMPLE / 2
	var dx := -r
	while dx <= r:
		var dy := -r
		while dy <= r:
			if macro.is_trail(center + Vector2i(dx, dy)):
				return true
			dy += _TRAIL_SUBSTEP
		dx += _TRAIL_SUBSTEP
	return false


# World tile → local map pixel (map is centred on the player).
func _to_local(tile: Vector2i, pt: Vector2i, origin: Vector2) -> Vector2:
	return Vector2(tile - pt) / _TILES_PER_SAMPLE * _cell + origin


func _in_map(p: Vector2) -> bool:
	return p.x >= 0.0 and p.y >= 0.0 and p.x <= _MAP_PX and p.y <= _MAP_PX


# Stable per-biome hue from its id (works for any biome, no hardcoded roster).
func _biome_color(biome: Resource) -> Color:
	return Color.from_hsv(float(absi(String(biome.id).hash()) % 360) / 360.0, 0.5, 0.7)


func _area_shade(area: Resource) -> Color:
	return Color.from_hsv(float(absi(String(area.type_id).hash()) % 360) / 360.0, 0.75, 0.95)
