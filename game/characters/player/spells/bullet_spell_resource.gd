extends SpellResource
class_name BulletSpellResource

## A spell that fires bullets: casting looses a burst — the fire_pattern fired every
## shot_interval along the caster's aim — until max_shots are spent, then the spell goes
## on cooldown. max_shots = 1 with a Single pattern is a plain projectile (what "fireball"
## is). A new bullet spell is one .tres composing a FirePattern and a BulletResource.

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
## Which lane the burst's shots fire down. TRACK re-samples the caster's aim every shot,
## so the stream follows them as they turn — dodged only by out-running its cadence.
## LOCK samples once as the burst starts and commits, which is what makes a long burst a
## readable line you step out of. INDEPENDENT commits to a random absolute angle instead,
## ignoring the caster entirely — the arena-painting spray (fae's rings, thornmess's
## spores). Ignored when max_shots is 1.
@export_enum("Track", "Lock", "Independent") var aim_mode: int = AIM_TRACK

const AIM_TRACK := 0
const AIM_LOCK := 1
const AIM_INDEPENDENT := 2
