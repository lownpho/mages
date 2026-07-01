class_name AreaResource extends Resource
## A sub-area *type* inside a biome (grove, thicket, den, boss clearing…). Types repeat:
## `required` types are baked ≥1× per biome, `optional` ones appear proportional to
## `weight` (Group E). An area overrides its biome's scenery dials and carries its own
## enemy roster + encounter templates, giving deeper areas a different look and danger.
##
## Scenery overrides use a -1 sentinel = "inherit the biome value"; use the resolve_*
## helpers so callers never special-case the sentinel.

@export var type_id: StringName                     ## identity / editor label (e.g. &"thicket")
@export var required: bool = false                  ## guaranteed ≥1 instance in its biome
@export_range(0.0, 10.0, 0.1, "or_greater") var weight: float = 1.0  ## relative instance count among optional types
@export var tags: Array[StringName] = []            ## e.g. &"boss", &"rare_den" — read by the specials pass (Group H)

@export_group("Scenery overrides (-1 = inherit biome)")
@export_range(-1.0, 0.5, 0.001) var patch_thickness: float = -1.0
@export_range(-1.0, 1.0, 0.01) var coverage: float = -1.0
@export_range(-1, 128, 1, "or_greater") var patch_width: int = -1
@export_range(-1.0, 0.2, 0.001) var decor_density: float = -1.0

@export_group("Enemies")
@export var roster: Array[PackedScene] = []         ## enemy scenes this area may spawn (also the coverage pool for Group H)
@export var encounters: Array[EncounterTemplate] = []


func resolve_patch_thickness(base: float) -> float:
	return base if patch_thickness < 0.0 else patch_thickness

func resolve_coverage(base: float) -> float:
	return base if coverage < 0.0 else coverage

func resolve_patch_width(base: int) -> int:
	return base if patch_width < 0 else patch_width

func resolve_decor_density(base: float) -> float:
	return base if decor_density < 0.0 else decor_density
