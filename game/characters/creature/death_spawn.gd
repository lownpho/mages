extends Resource
class_name DeathSpawn

## What a body leaves standing when it dies: a bloatcap's myceling brood, the three turrets a
## clustercap comes apart into. Fired on the same path as the loot drops, so a split is a line
## on the stat sheet rather than bespoke death code — and whatever the scene is, it arrives as
## an ordinary creature nobody spawned specially.
@export var scene: PackedScene
@export var count: int = 1
## Radius (tiles) around the corpse the brood scatters inside. 0 stacks them on the spot.
@export var spread_tiles: float = 1.0

func spawn(into: Node, at: Vector2) -> void:
	if scene == null or into == null:
		return
	for _i in count:
		var body: Node2D = scene.instantiate()
		# Both deferred, in this order: the corpse dies inside a collision callback so the
		# tree is busy, and the position only sticks once the node has a parent to be global
		# against. Deferred calls flush FIFO, so add_child lands first.
		into.add_child.call_deferred(body)
		var offset := Vector2(randf() * spread_tiles * GameConstants.PX_PER_TILE, 0.0)
		body.set_deferred("global_position", at + offset.rotated(randf() * TAU))
