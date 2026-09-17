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
## the enemy actually spawns (Biome and Zone rosters and Fixed encounters), so it can never drift from reality and
## a shared enemy files onto every biome it appears in. See GlobalBestiary._build_groups.
enum Rarity {COMMON, RARE, BOSS}
@export var rarity: Rarity = Rarity.COMMON
@export var max_health: int = 100
## What this creature is made of (see GameConstants.KIND_*). A spell whose `weakness` overlap
## hits it for double; everything else is unaffected — a mismatch is never punished. Most
## creatures carry one; two only where it's obvious (the moss golem is stone AND plant).
@export_flags("Insect:4", "Fungal:32") var kinds: int = 0
## Each entry is rolled independently on death, so a creature can drop several items at once.
## A Professor's gift is drawn from the pool these make up across a Biome (see SitePlanner).
@export var drops: Array[LootDrop] = []
## Bodies left behind on death, spawned on the same path as the drops — a bloatcap bursting
## into its brood, a clustercap coming apart into three turrets. Always fires; the roll is
## the drops' business, a split is the creature's whole point.
@export var death_spawns: Array[DeathSpawn] = []

## How this creature fills generated ordinary Rooms, wherever a roster fields it. Only the Entry
## challenge depends on the place.
@export_group("Encounters")
## Each ordinary encounter spawns between group_min and group_max of it. Challenge doesn't scale it.
@export_range(1, 20, 1, "or_greater") var group_min: int = 1
@export_range(1, 20, 1, "or_greater") var group_max: int = 1
## Relative chance of being drawn among an encounter's eligible types.
@export_range(1, 100, 1, "or_greater") var weight: int = 1
## Above 0 it is a Hazard: never drawn into an encounter or taught, but spread over every Testing
## and Teaching room's floor at this many per walkable tile once eligible. Challenge doesn't scale it.
@export_range(0.0, 0.25, 0.0005, "or_greater") var hazards_per_tile: float = 0.0


func is_hazard() -> bool:
	return hazards_per_tile > 0.0


## The id the Bestiary and the World file this creature under: its folder name under
## characters/enemies/. A summon's injected stats carry no resource_path, so they yield &"".
func enemy_id() -> StringName:
	return &"" if resource_path.is_empty() else StringName(resource_path.get_base_dir().get_file())
