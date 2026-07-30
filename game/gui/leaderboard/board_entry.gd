class_name BoardEntry
extends RefCounted

## One player's line in the leaderboard table: the union of what every board says about them.
## Each metric is its own Talo leaderboard, so a player is normally absent from some of them —
## the ratio board excludes accounts under RATIO_MIN_DAMAGE_DEALT, the deaths board excludes
## accounts that have never died. MISSING marks "not on that board": the row draws a dash and
## every sort drops it to the bottom, since MISSING is below any real score.

enum Sort {KILLS, DEATHS, RATIO, RECENT}

const MISSING := -1.0

## One hue per metric, worn by BOTH the column's numbers and its sort glyph. With no labels
## anywhere, matching colour is what says which header a number belongs to — so these are load
## bearing, not decoration. Green reads as tally, orange as the hot/bad one, cyan as the cool
## stat hue; the recency column is a creature icon and keeps its own colours. Deaths are orange
## rather than red for two reasons: RED is a dark-value hue that goes muddy at the dimmed alpha
## an inactive glyph wears, and it stays reserved for "something is wrong" (the offline emblem).
const COLORS: Array[Color] = [Palette.LIME, Palette.ORANGE, Palette.CYAN, Palette.WHITE]

var player_id := ""
var alias := ""
var kills := MISSING  ## distinct enemy types killed
var deaths := MISSING
var ratio := MISSING  ## damage dealt / taken
var last_death := MISSING  ## unix timestamp of their newest death_feed entry
var killer := ""  ## enemy id that landed it, "" when the death went unattributed
var bestiary: Dictionary = {}  ## their kill map, carried on the unique_kills entry's prop


func metric(sort: Sort) -> float:
	match sort:
		Sort.KILLS:
			return kills
		Sort.DEATHS:
			return deaths
		Sort.RATIO:
			return ratio
		_:
			return last_death
