extends CharacterBody2D

## One piercing light: flies straight and damages every enemy Hurtbox it
## crosses. It sits on the player-bullets layer so hurtboxes see it, but stays
## out of the "bullets" group so they don't despawn it — that's the piercing.
## Enemies aren't in its collision mask either; only walls stop it. Dies on
## walls, off-screen, or after a fallback lifetime (whichever comes first).

const LIFETIME = 3.0

var damage: int = 0
var texture: Texture2D
## Set by the spawner: how long the light hangs in place before flying off.
var launch_delay: float = 0.0

var _launched: bool = false

func _ready() -> void:
	if texture:
		$Sprite2D.texture = texture
	$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)

	if launch_delay > 0.0:
		var launch_timer := Timer.new()
		launch_timer.one_shot = true
		launch_timer.autostart = true
		launch_timer.wait_time = launch_delay
		launch_timer.timeout.connect(_launch)
		add_child(launch_timer)
	else:
		_launch()

func _launch() -> void:
	_launched = true
	# The lifetime clock starts at launch, so a long stagger can't eat into
	# the flight range.
	var lifetime_timer := Timer.new()
	lifetime_timer.one_shot = true
	lifetime_timer.autostart = true
	lifetime_timer.wait_time = LIFETIME
	lifetime_timer.timeout.connect(queue_free)
	add_child(lifetime_timer)

func _physics_process(delta: float) -> void:
	if not _launched:
		return
	if move_and_collide(velocity * delta):
		queue_free()

func get_damage() -> int:
	return damage
