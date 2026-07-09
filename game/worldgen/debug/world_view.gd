extends Node2D
## Debug view 1: the biome grid as colored cells, border-contract
## crossings as ticks on shared edges at their true slot positions, and world-unique room
## homes as dots in their host cell.

# Top margin leaves room for the seed console bar; the rest fits the window.
const TOP := 56.0
const MARGIN := 24.0

var _spec: WorldSpec = null
var _config: GenConfig = null


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)


func set_data(spec: WorldSpec, config: GenConfig) -> void:
	_spec = spec
	_config = config
	queue_redraw()


func _draw() -> void:
	if _spec == null:
		return
	var view := get_viewport_rect().size
	var cell := minf((view.x - 2.0 * MARGIN) / _spec.grid_w, (view.y - TOP - MARGIN) / _spec.grid_h)
	var origin := Vector2((view.x - cell * _spec.grid_w) * 0.5, TOP)
	var font := ThemeDB.fallback_font
	var s := float(_config.biome_slots)

	# Cells: unclaimed = dark sealed mass, no label. Biome labels once per placement (top-left).
	for y in _spec.grid_h:
		for x in _spec.grid_w:
			var bid := _spec.biome_at(Vector2i(x, y))
			var rect := Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell))
			if bid == &"":
				draw_rect(rect, Color(0.12, 0.12, 0.14))
				draw_rect(rect, Color.BLACK, false, 2.0)
				continue
			var biome := _config.biome_by_id(bid)
			draw_rect(rect, biome.display_color if biome else Color.MAGENTA)
			draw_rect(rect, Color.BLACK, false, 2.0)
	for p in _spec.placements:
		var prect := Rect2(origin + Vector2(p.rect.position) * cell, Vector2(p.rect.size) * cell)
		draw_rect(prect.grow(-1.0), Color.BLACK, false, 3.0)   # region outline over the cell grid
		draw_string(font, prect.position + Vector2(10, 24), String(p.id),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)

	# Contract ticks — only on edges where the two cells belong to DIFFERENT biomes (a contract
	# exists exactly there). Fraction along the edge = (slot + door-center-within-slot) / slots.
	for y in _spec.grid_h:
		for x in _spec.grid_w:
			var a := Vector2i(x, y)
			var abid := _spec.biome_at(a)
			if abid == &"":
				continue
			if x + 1 < _spec.grid_w:
				var bbid := _spec.biome_at(Vector2i(x + 1, y))
				if bbid != &"" and bbid != abid:
					var edge_x := origin.x + (x + 1) * cell
					for c in _spec.get_contract(a, Vector2i(x + 1, y)):
						var f: float = (c.slot_index + (c.tile_offset + c.width * 0.5) / _config.room_slot_tiles) / s
						var py: float = origin.y + y * cell + f * cell
						draw_line(Vector2(edge_x - 7, py), Vector2(edge_x + 7, py), Color.RED, 3.0)
			if y + 1 < _spec.grid_h:
				var bbid := _spec.biome_at(Vector2i(x, y + 1))
				if bbid != &"" and bbid != abid:
					var edge_y := origin.y + (y + 1) * cell
					for c in _spec.get_contract(a, Vector2i(x, y + 1)):
						var f: float = (c.slot_index + (c.tile_offset + c.width * 0.5) / _config.room_slot_tiles) / s
						var px: float = origin.x + x * cell + f * cell
						draw_line(Vector2(px, edge_y - 7), Vector2(px, edge_y + 7), Color.RED, 3.0)

	for ur in _spec.unique_rooms:
		# world_slot / biome_slots = fractional cell position.
		var pos: Vector2 = origin + (Vector2(ur.world_slot) + Vector2(0.5, 0.5)) / s * cell
		draw_circle(pos, 6.0, Color.GOLD)
		draw_circle(pos, 6.0, Color.BLACK, false, 1.5)
		draw_string(ThemeDB.fallback_font, pos + Vector2(8, 4), String(ur.type_id),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
