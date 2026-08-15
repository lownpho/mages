extends SpellResource
class_name NopeResource

@export_group("Nope")
## Total damage the bubble soaks before it breaks. 0 = unlimited for the
## channel's duration.
@export var absorb_amount: int = 0
## Fraction of the damage it soaks that comes back as health.
@export_range(0.0, 1.0, 0.01) var leech_fraction: float = 0.0
