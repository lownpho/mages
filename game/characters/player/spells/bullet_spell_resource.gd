extends SpellResource
class_name BulletSpellResource

## A spell that fires bullets: casting looses a burst — the fire_pattern fired
## every shot_interval along the caster's aim — until max_shots are spent, then
## the spell goes on cooldown. max_shots = 1 with a Single pattern is a plain
## single projectile (what "fireball" is). The behaviour lives in the generic
## bullet_spell.tscn effect; a new bullet spell is one .tres composing a
## FirePattern and a BulletResource, no code — and any caster can cast it.

@export_group("Bullet Spell")
@export var fire_pattern: FirePattern
## The projectile this spell fires — art, kinematics, behaviours — authored inline, so
## the spell is self-contained and tuning it touches nothing else. It carries no damage.
@export var bullet: BulletResource
## What this particular cast hits for, scaled from the caster's stats. Lives on the
## spell, not the bullet, so power is per-caster while the bullet stays shared.
@export var damage: ScalingProfile
## Seconds between shots within the burst (ignored when max_shots is 1).
@export var shot_interval: float = 0.25
## Shots in one burst; 1 is a single projectile.
@export var max_shots: int = 6
## Degrees the aim drifts per shot within the burst, so a pattern's gaps move shot to shot
## instead of firing the same lanes every time — a ring wave reads as a slow spiral to weave
## through rather than a static wall. 0 = every shot on the same bearing.
@export var rotation_per_shot: float = 0.0
## Ignore the caster's aim: the burst starts from a random absolute angle and never tracks.
## The arena-painting spray (fae's rings, thornmess's spores) rather than an aimed burst.
@export var aim_independent: bool = false
