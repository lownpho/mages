extends CanvasLayer

## The title screen's living backdrop: the real World, planned from a fresh seed each visit,
## drifting slowly over the spawn Room. It stays hidden until the plan and the spawn's chunks are
## ready and then fades in; the menu draws its first frame before planning holds the main thread.
## New starts the Run in this very World by reusing `graph`.
##
## Deliberately INERT. What turns a World into a Run is world.gd: its spawners, GlobalMap and
## GameState's saves. None of them are here, so nothing spawns, nothing fights and no save file is
## touched. The seed is local; GameState.active_seed belongs to the Run until New takes this plan.

## The World is planned and fading in.
signal planned

const CONTENT := "res://generation/world/"
## Radius of the drift, in px. Small on purpose: it has to stay inside the spawn Room.
const DRIFT_RADIUS := 32.0
const DRIFT_SECONDS := 60.0  ## one circuit; slow enough to read as ambient rather than as motion
const FADE_SECONDS := 0.5

## The planned World, for New to reuse; null until planned.
var graph: WorldGraph = null

@onready var _world: Node2D = $World
@onready var _streamer: ChunkStreamer = %Streamer
@onready var _eye: Node2D = %Eye

var _center := Vector2.ZERO
var _elapsed := 0.0


func _ready() -> void:
	_world.modulate.a = 0.0
	set_process(false)
	# Next frame, once the menu has drawn. The connection goes with this node if the title is left first.
	get_tree().process_frame.connect(_plan, CONNECT_ONE_SHOT)


func _plan() -> void:
	# The title was left before its first frame (New pressed at once, or a `-- seed=` launch).
	if not is_inside_tree():
		return
	var content := ContentLoader.load_content(CONTENT)
	if not content.is_valid():
		push_error("World content has problems:\n" + content.report())
		return
	graph = WorldGraph.generate(content, maxi(randi(), 1))
	if graph == null:
		return
	_streamer.build_world(graph)
	_center = _streamer.spawn_position()
	_streamer.target = _eye
	_drift(0.0)
	_streamer.prepare()
	set_process(true)
	create_tween().tween_property(_world, "modulate:a", 1.0, FADE_SECONDS)
	planned.emit()


func _process(delta: float) -> void:
	_drift(delta)


# Two halves of one pan: the eye is where the streamer believes the viewer is (so it knows which
# chunks to keep loaded), and this layer's offset is what actually puts that spot on screen. A
# Camera2D can't do the second half — it transforms the default canvas, which would drag the menu
# along with the scenery.
#
# The offset is deliberately NOT rounded to whole game pixels. The project stretches in
# `canvas_items` mode, so the frame is rasterised at window resolution with a scaled canvas
# transform rather than into a 320x180 buffer — a fractional offset is real, and lands the layer
# on an exact device pixel. Snapping it instead pins the view for ~18 frames at this drift speed
# and then jumps a whole tile-pixel, which reads as a stutter. Tiles stay crisp either way, since
# nearest filtering keeps every source pixel a solid block.
func _drift(delta: float) -> void:
	_elapsed += delta
	var angle := TAU * _elapsed / DRIFT_SECONDS
	_eye.global_position = _center + Vector2(DRIFT_RADIUS, 0).rotated(angle)
	offset = get_viewport().get_visible_rect().size * 0.5 - _eye.global_position
