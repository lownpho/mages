extends CanvasLayer

## The title screen's living backdrop: a real world, built by the real generator from a fresh seed
## each visit, drifting slowly over the room the player would spawn into.
##
## Deliberately INERT. What turns a generated world into a *run* is world.gd, not the streamer: it
## bridges the streamer's biome_entered onto GlobalEvent (which the bestiary writes to disk),
## emits world_ready, and calls GameState.persist(). None of that happens here. There is no
## EntitySpawner either, so nothing spawns, nothing fights, and no save file is touched. The
## seed is local — GameState.active_seed
## still belongs to the run, so what you see here is never the world New or Continue gives you.

## Radius of the drift, in px. Small on purpose: it has to stay inside the spawn room rather than
## wander into the void past the world's finite edge.
const DRIFT_RADIUS := 32.0
const DRIFT_SECONDS := 60.0  ## one circuit; slow enough to read as ambient rather than as motion

@onready var _streamer: WorldStreamer = %Streamer
@onready var _eye: Node2D = %Eye

var _center := Vector2.ZERO
var _elapsed := 0.0


func _ready() -> void:
	_streamer.build_world(randi())
	_center = _streamer.find_spawn_position()
	_streamer.target = _eye
	_drift(0.0)


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
