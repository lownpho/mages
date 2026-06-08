# Enemy Behaviour Composition

Enemies are assembled from reusable behaviour nodes in the editor rather than written as a script
per enemy. Most new enemies are just a scene file.

## The pieces

An enemy is three things:

- **The body** (`enemy.gd`) — the creature itself: health, sprite, hurtbox, and a few helpers
  (find the player, fire a probe, play an animation). It holds no AI, and every enemy shares it.
- **Behaviours** — one node per state of mind: stand and watch, stroll, chase, fire in range.
  Each does its own job and decides when to hand off to another. They live in a shared library and
  get reused across enemies.
- **The FSM** — the body's state machine. The behaviours are its children; one is active at a
  time, and they switch between each other.

So an enemy is one body plus a state machine full of behaviour nodes. What makes it feel like
*that* enemy is which behaviours are in the machine and how they hand off.

## Anatomy of the small demon

The demon watches for the player, chases, and fires when close. Its tree:

```
SmallDemon            (body — enemy.gd)
├─ AnimatedSprite2D
├─ Hurtbox
├─ DetectProbe        (RayCast2D — detect range)
├─ ChaseProbe         (RayCast2D — longer "keep chasing" range)
├─ AttackProbe        (RayCast2D — short firing range)
├─ Weapon
└─ FSM   (initial_state = "Idle")
   ├─ Idle
   ├─ Wander
   ├─ Chase
   └─ Attack
```

Each node under `FSM` is a behaviour, and its name is the state name. A behaviour doesn't hardcode
which probe to read or which state to go to next; those are exported fields you set in the
inspector. The demon's `Idle` node is told to watch through `DetectProbe` and switch to `Chase` on
sight. Its `Attack` node is told to fire `Weapon` while `AttackProbe` reaches the player, and drop
back to `Chase` otherwise.

Ranges are probes, not numbers. Each `RayCast2D` points at the player every frame, and "in range"
just means the ray reaches them. The rays hit terrain too, so the same check covers line of sight.
Tune a range by changing the probe's length.

## Adding a new enemy

Mostly editor work:

1. Copy an existing enemy with a similar shape. You inherit the body, sprite setup, probes,
   weapon, and a wired state machine.
2. Swap art and stats: sprite sheet, `max_health`, collision shape, weapon `.tres`.
3. Adjust the behaviours: drag probe lengths to set ranges, set speeds and timings, and add or
   remove behaviour nodes if the flow differs (re-pointing the hand-off states as you go).
4. Place it in the world.

If the enemy needs something no existing behaviour covers, that's a new behaviour: a small script
extending `Behaviour`. The ones under `characters/enemies/behaviours/` are the pattern to follow.

The `add-enemy` skill has the full checklist.
