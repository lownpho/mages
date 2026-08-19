extends Resource
class_name CreatureResource

## Per-creature stat sheet — the scalar balance values that belong to the creature as a
## whole. Casters and movement speeds are deliberately NOT here: a creature can have
## several of each (golem and longleg carry two casters; movement speed differs per
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
## What this creature is made of (see GameConstants.KIND_*). A spell whose `weakness` overlap
## hits it for double; everything else is unaffected — a mismatch is never punished. Most
## creatures carry one; two only where it's obvious (the moss golem is stone AND plant).
@export_flags("Insect:4", "Fungal:32") var kinds: int = 0
## Each entry is rolled independently on death, so a creature can drop several items at once.
@export var drops: Array[LootDrop] = []
## Bodies left behind on death, spawned on the same path as the drops — a bloatcap bursting
## into its brood, a clustercap coming apart into three turrets. Always fires; the roll is
## the drops' business, a split is the creature's whole point.
@export var death_spawns: Array[DeathSpawn] = []
