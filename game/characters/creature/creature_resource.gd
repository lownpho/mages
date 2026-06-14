extends Resource
class_name CreatureResource

## Per-creature stat sheet — the scalar balance values that belong to the creature as a
## whole. Weapons and movement speeds are deliberately NOT here: a creature can have
## several of each (golem and longleg carry two weapons; movement speed differs per
## FSM state), so those stay on the scene's behaviour nodes and their own .tres.
## display_name is an editor-facing label only — no code reads it.
@export var display_name: String = ""
@export var max_health: int = 100
## Each entry is rolled independently on death, so a creature can drop several items at once.
@export var drops: Array[LootDrop] = []
