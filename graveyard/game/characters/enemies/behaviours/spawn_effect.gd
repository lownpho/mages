extends Behaviour
class_name SpawnEffect

# A telegraph beat: spawns one cosmetic effect scene, holds in an animation for a fixed
# duration, then hands off. Carries no combat logic itself — it's the wind-up/flourish
# that fronts a heavier state (a summon, a phase change), spawned as its own node so it
# outlives this transition and cleans itself up.

@export var effect_scene: PackedScene
@export var duration: float = 1.2
@export var play_anim: String = "summon"
@export var done_state: String = "Pattern"

var _timer: Timer

func _ready() -> void:
	super()
	_timer = creature.make_timer(func(): creature.fsm.transition_to(done_state))

func enter() -> void:
	creature.velocity = Vector2.ZERO
	creature.play(play_anim)
	if effect_scene:
		var fx: Node2D = effect_scene.instantiate()
		fx.global_position = creature.global_position
		get_tree().root.add_child.call_deferred(fx)
	_timer.start(duration)

func exit() -> void:
	_timer.stop()
