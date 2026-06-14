extends Resource
class_name EnemyResource

## Per-enemy stat sheet — the scalar balance values that belong to the enemy as a
## whole. Weapons and movement speeds are deliberately NOT here: an enemy can have
## several of each (golem and longleg carry two weapons; movement speed differs per
## FSM state), so those stay on the scene's behaviour nodes and their own .tres.
@export var display_name: String = ""
@export var max_health: int = 100
@export var skill: int = 0
## Each entry is rolled independently on death, so an enemy can drop several items at once.
@export var drops: Array[LootDrop] = []
