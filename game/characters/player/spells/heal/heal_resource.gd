extends SpellResource
class_name HealResource

## Heal restores health from a ScalingProfile computed on the caster's stats
## (defence-scaled per the design — the survivability stat feeds the
## survivability button). Intrinsic scaling lives here, not on SpellResource:
## only effects that resolve a number from the resource itself carry one.
@export var amount: ScalingProfile
