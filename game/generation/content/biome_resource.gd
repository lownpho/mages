class_name BiomeResource
extends Resource
## A Biome, authored in biomes/<id>/biome.tres. The folder name is its id, and the .tres files in
## zones/ next to it are its Zones.

## The Challenge its route rises to. An Ideal-path Biome starts at the previous Biome's exit (the
## first at 0); a Side route starts at its attachment's Challenge.
@export_range(0, 50, 1, "or_greater") var exit_challenge := 0
## Enemy -> Entry challenge, shared by every Zone.
@export var roster: Dictionary[CreatureResource, int] = {}
## Optional; omit for a Biome without a Boss encounter.
@export var boss: FixedEncounterResource
## Keep this Biome generated, but close its borders, so nothing leads in or out of it.
@export var sealed := false

## The eight spatial knobs. Zones inherit them. The ranges are the debug sliders' ranges.
@export_group("Shape")
## Typical Room diameter in tiles.
@export_range(16, 64, 1) var room_size := 32
## How far Room borders wander, in tiles.
@export_range(0.0, 12.0, 0.5) var border_warp := 4.0
## Chance of a loop Passage between neighbouring ordinary Rooms.
@export_range(0.0, 1.0, 0.05) var loops := 0.3
## Chance of a shortcut where route stretches fold alongside one another.
@export_range(0.0, 0.8, 0.05) var shortcuts := 0.2
## Passage width in tiles.
@export_range(2, 12, 1) var passage_width := 5
## Share of the floor rocks may cover that turns to rock.
@export_range(0.0, 0.6, 0.01) var rockiness := 0.05
## How deep the wall on each side of a Room border is, in tiles.
@export_range(1.0, 6.0, 0.5) var wall_depth := 1.0
## How far wall_depth wanders along a border, in tiles either way; it never drops below one.
@export_range(0.0, 4.0, 0.5) var wall_variation := 0.0

@export_group("Presentation")
## Floor, wall, rock and decoration art, and minimap colours.
@export var presentation: BiomePresentation
## Chance of decoration on an eligible floor tile. A Zone may override it.
@export_range(0.0, 1.0, 0.005) var decoration_density := 0.0

@export_group("Objects")
@export_range(0, 10, 1, "or_greater") var professors := 0
@export var signs: Array[SignResource] = []
## Scene -> weight for Breather Objects, added to each Zone's own.
@export var breather_objects: Dictionary[PackedScene, int] = {}
