class_name Palette

## The game's colour vocabulary: the Zughy 32 palette.
## https://lospec.com/palette-list/zughy-32
##
## Every hardcoded colour in the game references a constant here — art is authored in
## these 32 hues, so UI/VFX/minimap chrome must stay in the same set. Reference as
## `Palette.WHITE`, `Palette.RED`, etc. Derived shades (e.g. dimmed UI states) should be
## `.darkened()`/`.lightened()` steps of a palette constant rather than new literals.

# Warm — plums, skin, earth
const DARK_PLUM := Color("472d3c")
const WINE := Color("5e3643")
const ROSEWOOD := Color("7a444a")
const CLAY := Color("a05b53")
const TAN := Color("bf7958")
const APRICOT := Color("eea160")
const PEACH := Color("f4cca1")

# Greens
const LIME := Color("b6d53c")
const GREEN := Color("71aa34")
const GREEN_DARK := Color("397b44")
const TEAL_DARK := Color("3c5956")

# Neutrals (dark → light)
const BLACK := Color("302c2e")
const GREY_DARK := Color("5a5353")
const GREY := Color("7d7071")
const GREY_LIGHT := Color("a0938e")
const SILVER := Color("cfc6b8")
const WHITE := Color("dff6f5")

# Cyans & blues
const SKY := Color("8aebf1")
const CYAN := Color("28ccdf")
const BLUE := Color("3978a8")
const BLUE_DARK := Color("394778")

# Purples & pinks
const INDIGO := Color("39314b")
const PLUM := Color("564064")
const PURPLE := Color("8e478c")
const MAGENTA := Color("cd6093")
const PINK := Color("ffaeb6")

# Warm brights — the alert/damage hues
const YELLOW := Color("f4b41b")
const ORANGE := Color("f47e1b")
const RED := Color("e6482e")
const RED_DARK := Color("a93b3b")

# Muted blue-greys
const MAUVE := Color("827094")
const SLATE := Color("4f546b")

## All 32 in palette order — for tooling that needs to iterate the set.
const ALL: Array[Color] = [
	DARK_PLUM, WINE, ROSEWOOD, CLAY, TAN, APRICOT, PEACH,
	LIME, GREEN, GREEN_DARK, TEAL_DARK,
	BLACK, GREY_DARK, GREY, GREY_LIGHT, SILVER, WHITE,
	SKY, CYAN, BLUE, BLUE_DARK,
	INDIGO, PLUM, PURPLE, MAGENTA, PINK,
	YELLOW, ORANGE, RED, RED_DARK,
	MAUVE, SLATE,
]
