extends Node2D
## Room Lab canvas: draws a grid of independently-generated rooms to the right of the
## control panel. Two render modes: tile-class colors (default, same palette as the
## worldgen room view) or the biome's REAL tilesets (presentation preview — autotiled
## layers where the presentation declares them, probability-weighted scatter otherwise).
## P/M toggle the PROTECTED / reachability overlays across every cell; overlays, spawn
## markers, outlines and labels draw in both modes. Lays out from the window size
## (content scaling is disabled). cell_at_screen_pos() lets the lab pin a clicked cell.

const CLASS_COLORS := {
	RoomBuilder.FLOOR: Color(0.12, 0.12, 0.16),
	RoomBuilder.WALL: Color(0.78, 0.76, 0.68),
	RoomBuilder.BLOCKER: Color(0.47, 0.45, 0.42),
	RoomBuilder.DECOR_FLOOR: Color(0.16, 0.28, 0.18),
}

const CELL_GAP := 10.0
const CELL_TOP := 12.0

var panel_width := 320.0
var show_protected := false
var show_reach := false
var presentation := false

var _config: GenConfig = null
var _outputs: Array = []      ## of RoomOutput
var _seeds: Array = []        ## per-cell generation seeds, parallel to _outputs
var _cols := 1
var _rows := 1
var _pres_root: Node2D = null


func _ready() -> void:
	get_viewport().size_changed.connect(_relayout)
	_pres_root = Node2D.new()
	add_child(_pres_root)


func set_data(config: GenConfig, outputs: Array, seeds: Array, cols: int, rows: int) -> void:
	_config = config
	_outputs = outputs
	_seeds = seeds
	_cols = maxi(cols, 1)
	_rows = maxi(rows, 1)
	_relayout()


func toggle_protected() -> void:
	show_protected = not show_protected
	queue_redraw()


func toggle_reach() -> void:
	show_reach = not show_reach
	queue_redraw()


func set_presentation(on: bool) -> void:
	presentation = on
	_relayout()


func _relayout() -> void:
	_rebuild_pres()
	queue_redraw()


# --- Layout (shared by draw, hit-test, and the presentation tilemaps) ------------------------

## [origin: Vector2, cell_size: Vector2] for grid cell i, or [] when the window is too small.
func _cell_layout(i: int) -> Array:
	var view := get_viewport_rect().size
	var area_x := panel_width + CELL_GAP
	var area_w := view.x - area_x - CELL_GAP
	var area_h := view.y - CELL_TOP - CELL_GAP
	var cell_w := (area_w - (_cols - 1) * CELL_GAP) / _cols
	var cell_h := (area_h - (_rows - 1) * CELL_GAP) / _rows
	if cell_w <= 4.0 or cell_h <= 4.0:
		return []
	var col := i % _cols
	@warning_ignore("integer_division")
	var row := i / _cols
	return [Vector2(area_x + col * (cell_w + CELL_GAP), CELL_TOP + row * (cell_h + CELL_GAP)),
			Vector2(cell_w, cell_h)]


## Room-area layout inside a cell: [origin: Vector2, ppt: float] (label strip reserved).
func _room_layout(out: RoomOutput, cell_pos: Vector2, cell_size: Vector2) -> Array:
	var draw_h := cell_size.y - 16.0
	var ppt := minf(cell_size.x / out.width, draw_h / out.height)
	return [cell_pos + Vector2((cell_size.x - ppt * out.width) * 0.5, 0.0), ppt]


## Grid index under a screen position, or -1 outside every cell.
func cell_at_screen_pos(pos: Vector2) -> int:
	for i in _outputs.size():
		var lay := _cell_layout(i)
		if lay.is_empty():
			continue
		if Rect2(lay[0], lay[1]).has_point(pos):
			return i
	return -1


# --- Presentation preview ---------------------------------------------------------------------

func _rebuild_pres() -> void:
	for c in _pres_root.get_children():
		c.queue_free()
	if not presentation or _config == null:
		return
	for i in _outputs.size():
		var out: RoomOutput = _outputs[i]
		var lay := _cell_layout(i)
		if out == null or lay.is_empty():
			continue
		var rlay := _room_layout(out, lay[0], lay[1])
		var holder := Node2D.new()
		holder.position = rlay[0]
		holder.scale = Vector2.ONE * (rlay[1] / GameConstants.PX_PER_TILE)
		_pres_root.add_child(holder)
		_fill_room_tiles(holder, out, _seeds[i] if i < _seeds.size() else 0)


func _presentation_for(biome_id: StringName) -> BiomePresentation:
	var b := _config.biome_by_id(biome_id)
	if b != null and b.presentation != null:
		return b.presentation
	var start := _config.biome_by_id(_config.starting_biome)
	return start.presentation if start != null else null


## One room's four tile layers under `holder`. Autotiled layers use Godot's terrain
## connect solver (visually equivalent to the streamer's deterministic mask match);
## scatter layers pick probability-weighted variants from a room-seeded RNG.
func _fill_room_tiles(holder: Node2D, out: RoomOutput, room_seed: int) -> void:
	var pres := _presentation_for(out.biome_id)
	if pres == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = room_seed
	var floor_layer := _make_layer(holder, pres.floor_tileset, -2)
	var bg_layer := _make_layer(holder, pres.object_bg_tileset, -1)
	var object_layer := _make_layer(holder, pres.object_tileset, 0)
	var wall_layer := _make_layer(holder, pres.wall_tileset, 1)

	var floor_cells: Array[Vector2i] = []
	var wall_cells: Array[Vector2i] = []
	for y in out.height:
		for x in out.width:
			var cell := Vector2i(x, y)
			var cls := out.tile_grid[y * out.width + x]
			floor_cells.append(cell)   # every solid also lays floor beneath (streamer rule)
			match cls:
				RoomBuilder.WALL:
					wall_cells.append(cell)
				RoomBuilder.BLOCKER:
					_scatter_cell(object_layer, cell, rng)
				RoomBuilder.DECOR_FLOOR:
					_scatter_cell(bg_layer, cell, rng)
				_:
					pass

	_fill_terrain_or_scatter(floor_layer, floor_cells, pres.floor_autotile, rng)
	_fill_terrain_or_scatter(wall_layer, wall_cells, pres.wall_autotile, rng)


func _make_layer(holder: Node2D, tileset: TileSet, z: int) -> TileMapLayer:
	if tileset == null:
		return null
	var layer := TileMapLayer.new()
	layer.tile_set = tileset
	layer.z_index = z
	holder.add_child(layer)
	return layer


func _fill_terrain_or_scatter(layer: TileMapLayer, cells: Array[Vector2i], autotile: bool,
		rng: RandomNumberGenerator) -> void:
	if layer == null or cells.is_empty():
		return
	if autotile:
		var tt := _first_terrain(layer.tile_set)
		if tt.x >= 0:
			layer.set_cells_terrain_connect(cells, tt.x, tt.y, false)
			return
	for cell in cells:
		_scatter_cell(layer, cell, rng)


## (terrain_set, terrain) of the first terrain-painted tile in source 0, or (-1, -1).
func _first_terrain(tileset: TileSet) -> Vector2i:
	if tileset == null or tileset.get_source_count() == 0:
		return Vector2i(-1, -1)
	var src := tileset.get_source(tileset.get_source_id(0)) as TileSetAtlasSource
	if src == null:
		return Vector2i(-1, -1)
	for i in src.get_tiles_count():
		var td := src.get_tile_data(src.get_tile_id(i), 0)
		if td != null and td.terrain_set >= 0 and td.terrain >= 0:
			return Vector2i(td.terrain_set, td.terrain)
	return Vector2i(-1, -1)


func _scatter_cell(layer: TileMapLayer, cell: Vector2i, rng: RandomNumberGenerator) -> void:
	if layer == null:
		return
	var ts := layer.tile_set
	if ts == null or ts.get_source_count() == 0:
		return
	var source_id := ts.get_source_id(0)
	var src := ts.get_source(source_id) as TileSetAtlasSource
	if src == null or src.get_tiles_count() == 0:
		return
	# Probability-weighted pick over the source's tiles (mirrors the streamer's scatter).
	var total := 0.0
	for i in src.get_tiles_count():
		var td := src.get_tile_data(src.get_tile_id(i), 0)
		total += td.probability if td != null else 1.0
	var r := rng.randf() * total
	for i in src.get_tiles_count():
		var coord := src.get_tile_id(i)
		var td := src.get_tile_data(coord, 0)
		r -= td.probability if td != null else 1.0
		if r <= 0.0:
			layer.set_cell(cell, source_id, coord)
			return
	layer.set_cell(cell, source_id, src.get_tile_id(0))


# --- Class-color mode + overlays -----------------------------------------------------------

func _draw() -> void:
	if _config == null or _outputs.is_empty():
		return
	for i in _outputs.size():
		var out: RoomOutput = _outputs[i]
		var lay := _cell_layout(i)
		if out == null or lay.is_empty():
			continue
		_draw_room(out, lay[0], lay[1], _seeds[i] if i < _seeds.size() else 0)


func _draw_room(out: RoomOutput, cell_pos: Vector2, cell_size: Vector2, room_seed: int) -> void:
	var w := out.width
	var h := out.height
	var rlay := _room_layout(out, cell_pos, cell_size)
	var origin: Vector2 = rlay[0]
	var ppt: float = rlay[1]
	var tile := Vector2(ppt, ppt)

	if not presentation:
		draw_rect(Rect2(origin, Vector2(w, h) * ppt), CLASS_COLORS[RoomBuilder.FLOOR])
		for y in h:
			var r := y * w
			for x in w:
				var c := out.tile_grid[r + x]
				if c != RoomBuilder.FLOOR:
					draw_rect(Rect2(origin + Vector2(x, y) * ppt, tile), CLASS_COLORS[c])
	if show_protected:
		var pc := Color(0.2, 0.9, 1.0, 0.35)
		for y in h:
			var r := y * w
			for x in w:
				if out.protected_map[r + x] == 1:
					draw_rect(Rect2(origin + Vector2(x, y) * ppt, tile), pc)
	if show_reach:
		var rc := Color(0.2, 1.0, 0.3, 0.22)
		for y in h:
			var r := y * w
			for x in w:
				if out.reachability_map[r + x] == 1:
					draw_rect(Rect2(origin + Vector2(x, y) * ppt, tile), rc)
	draw_rect(Rect2(origin, Vector2(w, h) * ppt), Color(1, 1, 1, 0.35), false, 1.0)

	# Spawn markers.
	var col := Color(0.9, 0.2, 0.2)
	for sp in out.spawns:
		if not (sp is Dictionary):
			continue
		var stile: Vector2i = sp.get("tile", Vector2i.ZERO)
		draw_circle(origin + (Vector2(stile) + Vector2(0.5, 0.5)) * ppt, maxf(2.0, ppt * 0.6), col)

	var label := "%s  %dx%d  %d spawns  seed %d" % [
		out.type_id, w, h, out.spawns.size(), room_seed]
	draw_string(ThemeDB.fallback_font, cell_pos + Vector2(2, cell_size.y - 3), label,
			HORIZONTAL_ALIGNMENT_LEFT, cell_size.x, 12, Color(0.82, 0.85, 0.9))
