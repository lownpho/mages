extends SpellResource
class_name NopeResource

@export_group("Nope")
## Mana drained per point of incoming damage while the shield holds.
## 0 = full absorb at no mana cost.
@export var mana_per_damage: float = 0.5
