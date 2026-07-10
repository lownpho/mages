extends Resource
class_name CreatureResource

## Per-creature stat sheet — the scalar balance values that belong to the creature as a
## whole. Weapons and movement speeds are deliberately NOT here: a creature can have
## several of each (golem and longleg carry two weapons; movement speed differs per
## FSM state), so those stay on the scene's behaviour nodes and their own .tres.
## display_name is an editor-facing label only — no code reads it.
@export var display_name: String = ""
## Bestiary icon — the creature's idle frame at native size, an AtlasTexture into the
## creature's own sprite sheet (never a scaled or redrawn copy).
@export var icon: Texture2D
## Bestiary ordering within a biome: commons first (alphabetical), rares after, boss last.
## Which biome page(s) an enemy is filed under is NOT stored here — it's derived from where
## the enemy actually spawns (the room spawn tables), so it can never drift from reality and
## a shared enemy files onto every biome it appears in. See GlobalBestiary._build_groups.
enum Rarity {COMMON, RARE, BOSS}
@export var rarity: Rarity = Rarity.COMMON
@export var max_health: int = 100
## Each entry is rolled independently on death, so a creature can drop several items at once.
@export var drops: Array[LootDrop] = []
