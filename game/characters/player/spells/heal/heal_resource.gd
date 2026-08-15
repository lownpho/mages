extends SpellResource
class_name HealResource

## How much health it restores, computed on the caster's stats. Defence-scaled per the
## design — the survivability stat feeds the survivability button.
@export var amount: ScalingProfile
