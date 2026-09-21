# Bosses

<!-- Hand-written, unlike enemies.md / biomes.md / spells.md. Edit here, not there. -->

Design rules for a Biome's Boss. They exist because bosses were easy and long at the same
time: the same flat loop for two to four minutes, with nothing the player had to read, answer
or lose. Length is intended; the flatness was not. Every rule below serves one goal: **a boss
is a sequence of things to answer, and the fight tightens while you answer them.**

A boss fight lasts 2–3 minutes and its HP is unchanged. Difficulty comes from structure,
pressure and escalation, never from a bigger health pool.

## Glossary

**Rotation**:
The ordered list of Phases a boss plays through, repeated until it dies. Order is authored,
never rolled.
_Avoid_: cycle, loop, pattern (the dispatcher CLASS that walks the Rotation is `Cycle` — see
Where it lives in code)

**Phase**:
One beat in the Rotation, played for its authored Reps, followed by its recovery Tail.
_Avoid_: stage

**Rep**:
One playthrough of a Phase's beat. Reps of a Phase are identical. 1–8, authored per Phase,
default 2.

**Tail**:
The recovery after a Phase's last Rep. The punish window. The only place a boss is soft.

**Free beat**:
A short non-counterable pause between Phases. At most 1.5s, never repeats.

**Intensity (M)**:
The single scalar that tightens the fight as Phases advance. Starts at 1.0, caps at 2.0.

**Counter**:
What the player must do to answer a Phase. Per-beat declared, one kind per beat.

**Distance profile**:
A boss's authored answer to the player running away. One of Siege, Hunter, Sniper.

## The shape of a fight

- A boss runs an **ordered Rotation** of Phases. It does not roll.
- A **Phase is one beat** with a declared Counter, played for its **Reps**, then its **Tail**.
- **Reps are identical.** Their only job is to let the player read a beat before the Rotation
  moves on. Nothing about a Rep may escalate.
- **Every Phase declares a Counter.** A Phase with nothing to answer is dead time and is not
  allowed. The burn window a player needs lives inside the Phase, as its Tail.
- A **Free beat** may sit between Phases: at most 1.5s. It is authored in one place on the
  Cycle rather than as a step of the Rotation (a Phase with no Counter is not allowed), so the
  same Free beat cannot recur as a Phase would — and the Phase before it is already closed
  while it runs, which is what makes it non-counterable pacing rather than a farm window.
- After the last Phase the Rotation **wraps** to the first. The Intensity carries across the
  wrap; it never resets between loops.
- 3–6 Phases per Rotation (the ceiling is Gnarlking's, whose sixth is a `once` desperation
  Phase: the loop the player actually reads is still five). Everything else about the Rotation is the boss's own grammar, not
  a shared template: Reps run 1–8, Tails 0.5–2.5s, and the length falls out per boss rather
  than every boss targeting the same 100–120s. A beat said once behind a 2.4s Tail and a beat
  said four times behind a 1.0s Tail are different fights, and that difference is free.

## Grammars, not templates

The rules above are a shared **vocabulary** — an ordered Rotation, one Counter per beat, a Tail
as the only soft moment. They are not a shared template. Two bosses built from the same four
Counter kinds can still be the same fight, and will be, unless each one's grammar differs. Every
boss must differ from its predecessor on all four of these:

- **Danger range** — where the fight wants the player. Fae wants you *away*: every one of her
  Phases is answered at distance or by leaving. Thornmess wants you *on top of it*, because a
  rooted thing's only openings are the commitments it locks itself into. Two bosses may not
  want the player in the same place.
- **Counter mix** — which kinds, and how many of each. The mix *is* the question the boss asks
  (a movement exam, an aggression exam). No two bosses open their Rotation with the same kind,
  and no boss repeats its predecessor's mix. rotmaw is the one exception on the shipped roster
  and it is an argued one: its Gape is Thornmess's PUNISH opener asked at the opposite range,
  and rotmaw is the first boss whose fight-level opener is a stage rather than a Phase. Counter kind is coupled to range — only a beat
  that ends with the player adjacent can be PUNISH — so a mix is really a statement about
  distance.
- **Tempo** — Rep counts and Tail lengths are character, not padding to reach a length. The
  same beat said once behind a long Tail is a different beat from one said twice behind a
  short one. Authors choose these per Phase deliberately; reaching for 2 Reps and a 1.0s Tail
  everywhere is how a roster of distinct bosses collapses into one.
- **Movement policy** — never moves, walks after you, or commits to charges. A committed rush
  in two bosses' Rotations reads as the same beat twice, so whichever boss owns a charge, the
  next one answers distance a different way.

## Intensity multiplier

The Rotation wrapping is what makes the fight long; **M is what makes the repeat worse.**
Reps do not escalate, so M is the only escalation axis in the design.

- **M rises +0.12 every time a Phase advances** — including across the wrap. It is a global,
  monotonic scalar for the whole fight, not a per-loop counter.
- **A clean Counter drops M by 0.12.** The player's play is the brake; a competent player
  rides most of the fight near ×1 and only a struggling one feels the spiral.
- **M is clamped to [1.0, 2.0].** The cap guarantees a boss fight always ends in a winnable
  state, and it means every dial below is bounded to a 2× swing, never a spiral.
- **M scales timing only.**
  | Dial | At M | Floor |
  |---|---|---|
  | telegraph / windup duration | base ÷ M | 0.35s |
  | Tail (punish window) | base ÷ M | 0.40s |
  | gap between Reps | base ÷ M | 0.30s |
  | movement speed | base × M | 75 px/s **cap** |

  Movement speed is the one dial bounded upward rather than downward: a boss closes the gap as
  it escalates, but never outruns the player's 80 px/s. It is read by a pursuit (Approach);
  Fae has none — her answer to distance is the Flit rush and her escort — and Gnarlking, the
  Hunter, is where it will bite. Thornmess's Uproot is the first walk a boss answers distance
  with, and at 32 px/s it is the slowest thing in the game; it stays that way.

  Damage and projectile speed are **never** scaled. Density is **never** scaled.
- The floors are not optional. The counter model rests on the player being able to read a
  telegraph; an escalation that makes a Phase unreadable breaks the promise the Phase's
  Counter was authored to keep. A ×2 boss is the same fight with less slack, not a new one.
- A ×2 cap makes windups halve, not shrink further. Author per-step factors (×0.8 windup,
  ×1.1 speed and so on) only as a way to choose the base numbers; the bound is M.

## Counters

Exactly one kind per beat, declared on the beat. Four kinds, each mapped to an event that
already exists — no new sensing.

| Kind | Credits when | Existing seam |
|---|---|---|
| **PUNISH** | the boss takes damage during its Tail | `incoming_damage_scale` under 1 |
| **WALL** | the boss slams head-on into a wall mid-charge | `Creature.dash_blocked` |
| **ADDS** | the boss's escort group clears | `clear_group` membership (exact — see below) |
| **UNTOUCHED** | the player took zero damage across the Phase | the player's `hurt` signal |

- An escort the boss itself called is counted **exactly**: every member, wherever it stands
  (`clear_radius_tiles = 0`). The radius the default exists for is a world-pack concern —
  streaming keeps a neighbouring room's pack loaded, so a straggler three rooms away must not
  pin a fight — and reading an escort with it is a cheese, because one live add led out of
  range then reads as a cleared one.
- A Counter credits **once per Phase** (a latch), so a Phase can only ever undo one step of M.
  UNTOUCHED counts damage from the Phase's own adds — the clause is "the player took none",
  and a boss whose add Phase is ADDS never asks the question. It is settled when the Phase's
  last Rep ends rather than at the end of the Tail: the Tail is the player's own window, and
  clipping a lingering hazard inside it is not a failure to answer.
- Counters are **positional or timing**, never spell-gated. A player with four random spells
  must always be able to answer every Phase with movement alone. Spell kinds, cloud
  empowerment and weakness damage are flavour, never the gate.
- A `Counter` that requires a specific drop is a bug, not a challenge.

## Health overlay

- HP is **not** a phase clock. M is.
- One **HP-gated desperation Phase** is allowed per boss: `health_max` ≤ 0.25, last in the
  Rotation, `priority` + `once` so it fires the instant the window opens and then never
  again. This is the one authored cliff on top of the smooth M curve, and it is where a boss
  reads as intimidating rather than merely faster.
- This reuses `health_min` / `health_max` exactly as the Thornmess and Gnarlking already do.

## Distance profiles

A boss must have an authored answer to the player walking away. Unanswered distance is how a
boss becomes a kiteable sponge — Fae is 28 px/s against the player's 80.

| Profile | Answer to distance |
|---|---|
| **Siege** | fills the floor: lingering hazards, summons, pools, area denial |
| **Hunter** | closes and stays: committed, dodgeable pursuit that cannot be shaken |
| **Sniper** | far is the losing position: long-range aimed volleys and full-arena patterns |

- Every boss authors **one primary profile**.
- Answering distance is not always a Phase. A boss may answer it **outside the Rotation** —
  `Cycle.lost_state` behind a `probe_path` — which is how a rooted boss walks after the player
  without the walk ever becoming a Phase with nothing to answer.
- The mirror of that is the **Reaction**: a beat played from the Phase boundary the Rotation has
  just reached, when the player is standing inside the boss's own reach. It is not a Phase — no
  Counter, no Reps, no move of the cursor — it takes the Free beat's slot and the order resumes
  where it was, which is what lets a boss say *charge if you leave, slam if you crowd* without
  either answer becoming a step of the sequence. Authored in one place on the Cycle
  (`reaction_state`, `reaction_probe_path`), and the beat it names keeps declaring its own
  reach: a reaction that cannot land does not fire, and the Rotation carries on. Its home is
  Gnarlking, whose slam is the two-tile answer to a player standing on it.
- Range is the one gate a Rotation cannot wait out — a cooldown lapses on its own and an escort
  dies on its own, but the player is range's clock — so a Phase held out of reach hands off to
  the walk rather than standing there (`Behaviour.range_open()`).
- A boss may author **one switch**, engaged at the second loop (M ≥ ~1.6), so the escalation
  can read as *the boss changed its answer to you*, not just faster numbers.
- Assignments: Fae **Siege → Sniper** (the Siege half is shipped; the Sniper half is not
  authored yet — see the reference instance), Thornmess **Siege**, Gnarlking **Hunter**,
  hive queen **Siege → Sniper**, Mother **Sniper**. rotmaw authors one per body rather than
  one per fight — maw **Sniper**, sporemother **Siege**, gnawer **Hunter** (via burrow), the ring
  **Siege** — which is what a multi-body fight buys instead of a switch.

## Multi-body fights

Everything above assumes one boss: one Rotation, one M, one corpse. A fight may instead be
several bodies in sequence, where killing one is what starts the next. `Cycle` and
`BossController` are per-scene, so this needs nothing new — but the rules read differently and
the differences are authored, not discovered:

- **One Rotation per body**, each obeying the whole contract on its own: 3–6 Phases, a Counter
  on every Phase, its own Tails and Reps.
- **One M per body.** A body's escalation dies with it, which is the point: killing one of two
  concurrent bodies retires its pressure as well as its damage, and that is the reward for
  reading which one to kill.
- **One HP-gated desperation Phase per body still**, and a body may spend it instead on the
  split — at zero rather than at a quarter.
- **Distance profile is per body**, not per fight. A fight that walks, then roots, then never
  moves again is a legitimate arc and a cheaper one than authoring a switch.
- The chain is `CreatureResource.death_spawns`, so **every body that still has to split needs
  its own `data`**. A body without a stat sheet is a leaf.
- An escort a body did not summon is its **armour**, not its cue. `clear_group` means "refuse
  to run while these stand", which is right for a boss holding its next brood back and wrong
  for one ringed by caps two corpses left: gated on them it would stand still through its own
  finale. `Behaviour.waits_for_escort` clears the gate while leaving the group answering for
  the ADDS Counter and the escort armour, which read `group_clear()` directly.
- A fed/plain pair is two **adjacent Phases**, not a `Gate` inside one Phase slot. `Cycle`
  resolves a Phase to a named `Behaviour` and counts its Reps on it, so a `Gate` there would
  hand off twice. Adjacent Phases cost nothing: exactly one of the pair is ever eligible,
  `_next_phase` skips the other, and M steps once.
- **A stage that follows concurrent bodies is gated on all of them.** Each carries the whole
  next stage on a `DeathSpawn` with the same `after_group`, and they share that group: a corpse
  with a sibling still standing leaves nothing, so the last to fall leaves it all. rotmaw's
  halves are `rotmaw_half`, and the ring arrives whole — core and three wardens — only after
  both. Without the gate each corpse fires its own share and the stages overlap.
- rotmaw is the first, and is built. The hive queen is expected to be the second.

## Failure and damage

- Player is 100 HP, has no i-frames, and defence is flat per-hit reduction. Every touching
  bullet hurts. Damage is therefore the cost of not answering.
- **Chip plus one big punish.** A missed Counter costs a cluster of small hits; the boss's
  signature move is a 25–40 damage punish behind a long, loud telegraph.
- **No single mistake ends a run.** Across a 2–3 minute fight chip alone already makes sloppy
  play lose. One-shots are reserved for nothing.
- Boss hits are the demonstration of the Counter: the signature move's telegraph is the
  question, and its Tail is the answer.

## Legibility

The player must be able to see that the fight is tightening and that answering it loosens it.
A brake the player cannot perceive is not a brake.

- **Animation and audio. No boss health bar.** There is none in the game today
  (`gui/` holds the Map and the Bestiary), and the rework does not add one.
- Every step of M visibly speeds the boss's idle and attack animation: a wind-up fitted to a
  shortened `cast_time`, a pursuit played at `base × M`, and the intensity baked into
  `Creature.play_fitted` so nothing has to remember to say it.
- An audio sting marks a step **up**; a distinct sting marks a rollback, so the player learns
  that Countering is what keeps the fight at ×1. **Not implemented yet**: the game has no
  audio system and no sound assets. `BossController.intensity_changed` and
  `Behaviour.countered` are the hooks, and the visible half is wired.
- Counters are discovered by reading the tell, not by an on-screen prompt.

## Stakes

- Bosses stay **optional**, per CONTEXT.md.
- Rewards are unchanged: the same drops, the same Bestiary page.
- A boss is worth fighting for its fight and its drop, not for a gate.

## Where it lives in code

- **`BossController`** — a node on each boss scene owning the ordered Rotation, M, the Phase
  cursor, the Rep count and the Counter latch. It also does the Counter detection, reading
  signals that already exist: the boss's hurtbox (PUNISH, during the open Tail), `dash_blocked`
  (WALL), the player's hurtbox (UNTOUCHED), and escort-group membership (ADDS, which also holds
  the escort's armour). One node, so the whole fight is comprehensible and testable away from
  the FSM.
- **`Behaviour.counter_kind`** — the per-beat declaration, with `countered` as the signal a
  crediting lands on. `Behaviour.reps`, `.tail` and `.rep_gap` are the per-Phase dials, and
  `Behaviour.window_open()` separates a window that has shut for good from a gate worth
  waiting out.
- **`Cycle`** — a dispatcher replacing `PatternPicker` for bosses: ordered Phases, authored
  Reps, the pauses (rep gap, Tail, Free beat) in one state, and the boss's answer to a player
  leaving the arena (`probe_path` / `lost_state`, so the walk out of range is not a Phase). It
  hands off to a Phase and the Phase hands back (`done_state = "Cycle"`). `PatternPicker` (roll)
  and `Gate` (ordered) stay as they are for everything else.
- **`Cycle.reaction_state` / `.reaction_probe_path`** — the proximity answer, mirror of
  `lost_state`'s distance answer: the beat to play instead of the Free beat at a Phase boundary,
  and the probe the player must be inside for it to fire. A reaction claims no Rep, declares no
  Counter and moves no cursor, so it can neither be farmed nor spend a Phase's punish Tail.
- **`Behaviour.range_open()`** — the range gate asked on its own, so a dispatcher knows the
  difference between a Phase that is waiting (a cooldown) and one that is never coming back on
  its own (the player left).
- **`Creature.reset_combat`** clears M with the rest of the fight: a rewound fight is a rewound
  fight (the 60s leash).

## Reference instance: Fae

The first boss, and the proof the skeleton covers all three counter families before it is
ported anywhere else.

| Phase | Beat | Counter kind | Reps |
|---|---|---|---|
| 1 | Ring Pulse — ring bursts of 8, 10 pulses | positional gap-walk → **UNTOUCHED** | 2 |
| 2 | Shotgun — 5-pellet cone, two volleys | cross the cone sideways → **PUNISH** | 2 |
| 3 | Flit — a committed rush with contact damage | sidestep / dash through → **UNTOUCHED** | 2 |
| 4 | Wisp Call — 4 wasps, armoured while they live | clear the adds → **ADDS** | 2 |
| 5 | Ring Storm — a 16-bullet ring, 3 pulses, ≤25% HP | gap-walk → **UNTOUCHED** | 1 |

- Free beat: a 1.2s pause between Phases (the chime pose is still to be authored; the pause is
  the mechanic).
- The 5s `Rest` Phase is **deleted**; the burn window is each beat's Tail (1.0–1.4s, ÷ M).
- HP stays 1500. Ring Pulse keeps its authored 10-pulse burst, so the Ring beat is the long one.
- Adds are 4 × `wasp.tscn` (18 HP) — an enemy already on the glade's Bestiary page. They join
  `pack_wisp` (a SummonResource `minion_group`), which is what the Phase gates on: the Rotation
  waits and Fae stays armoured at ×0.25 until they are dead.
- That wait is **bounded** (`Cycle.escort_hold`, 6s). A wasp parked behind scenery has no line
  of sight and no pathing round it, so an unbounded gate is a soft-lock; when the hold lapses
  Fae resumes, the armour comes off and the Phase's Counter is forfeit. Ignoring the adds costs
  the player the rollback, not the fight — and one live add can never read as a cleared one.
- Flit is a `ChargeDashResource` tuned down to Fae's size (150 px/s for 0.7s, 20 contact
  damage, two weak flank bolts) rather than a plain approach, because an UNTOUCHED Counter
  needs a beat that can actually touch you.
- Ring Storm is the HP-gated desperation Phase: last in the Rotation, `priority` + `once`.
- Profile: **Siege** — her ring pulses fill the floor and her wisps hunt you, so backing off
  trades space for adds. The **Sniper** switch at the second loop (a long-range volley) is not
  authored yet; it needs a long-range beat and a min-Intensity gate, and is worth doing when a
  second boss needs the same switch.

## Reference instance: Thornmess

The second boss, and the proof the skeleton carries two fights that do not look alike: Fae is a
movement exam you run *away* from, Thornmess is an aggression exam you run *at*. Its Counter mix
is Fae's inverted, its Reps are uneven where hers are uniform, and its Tails are twice as long.

| Phase | Beat | Counter kind | Reps | Tail |
|---|---|---|---|---|
| 1 | Rooted Bloom — 12-ring, 5 pulses, 3s armoured windup | run in and burn the long recovery → **PUNISH** | 1 | 2.4 |
| 2 | Thornfall — homing missiles, 4 shots | stay untouchable through the volley → **UNTOUCHED** | 2 | 1.0 |
| 3 | Bitter Spit — shotgun cone, 4 volleys | cross the cone and burn → **PUNISH** | 4 | 1.8 |
| 4 | Seedlings — 6 rooted plants (seedling / rosebud / thornthrower) | clear the growth → **ADDS** | 1 | 1.6 |
| 5 | Spore Storm — 16-ring, 3 pulses, ≤25% HP | gap-walk → **UNTOUCHED** | 1 | 2.4 |

- **The mix is the point.** PUNISH ×2 / UNTOUCHED ×2 / ADDS ×1 against Fae's UNTOUCHED ×3 /
  PUNISH / ADDS — the same four kinds, asking the opposite question. It also **opens** on a
  different kind from hers (a PUNISH commitment, not a pattern to dodge), because the first
  thing the fight asks is then the thing it asks all fight: come at it.
- Free beat: a 1.2s re-rooting pause (the pose is still to be authored; the pause is the
  mechanic). The 4s `Rest` Phase is **deleted** — every burn window is a beat's own Tail, which
  is the same trade Fae's rebuild made.
- **Every Phase is slow and committed**, so the fight is about spending windows rather than
  dodging. That is why the Reps are `1,2,4,1,1` and not 2 everywhere (the cheap spit repeats,
  the commitments are said once) and why the Tails run to 2.4s: a rooted half-tonne recovers
  slowly.
- **Nothing moves during a Phase.** `Uproot` is deleted as a Phase and becomes the answer to
  distance instead — `Cycle.lost_state` behind `DetectProbe`, a 32 px/s walk (scaled and capped
  like any pursuit) that hands back to the Rotation. It starts at the next hand-off, so a Phase
  is never interrupted by distance: being rooted means committing to whatever it is doing.
- **A Phase's spell should not author a cooldown.** The Rotation is the pacing, so `cooldown`
  on a boss's cast is a leftover from the PatternPicker era — and a live hazard, because a
  cooling beat is overtaken by the next runnable one and the authored order silently drops a
  Phase. Thornmess's three authored cooldowns (3s, 6s, 7s) are zeroed; what is left is the 1s
  resource default, which no lap is short enough to notice. Fae never authored one at all.
- **Spore Storm is cut from its authored 10 pulses to 3.** Legibility, not balance: 15.7s of
  in-flight 25-damage rings buries its own Tail, so there is no punish window left to open.
  Fae's Ring Storm is 3 pulses for the same reason.
- **Rooted Bloom keeps its spell and loses its `health_min`.** Under a Rotation the HP gate
  belongs to the desperation Phase alone, so the field is dead there and must not be authored.
- **Seedlings are an escort, not terrain.** `minion_group = &"pack_seed"`,
  `clear_radius_tiles = 0` (exact), escort armour while they stand, and a **lifetime shorter
  than a lap** — the summon authors 0 (permanent) today, which would leave a straggler failing
  the next lap's escort gate for the rest of the fight. The **hold is sized to the escort**, not
  copied from Fae: six plants average ~40 HP against her four wasps' 18, so it is 12s where hers
  is 6s, and it has to lapse before the escort's own 20s timer does — otherwise the rollback is
  handed out by a clock instead of by the player killing anything.
- **WALL is not here.** A committed charge would be Fae's Flit with a wall, and it contradicts
  "the rooted capstone. It stays on the ground". The family's home is Gnarlking.
- Profile stays **Siege**, and that is now a claim the boss can cash: bloom rings reach 14 tiles,
  spores 18, and the seedlings claim floor. Distance is answered by reach, then by a walk.

## Reference instance: Gnarlking

The third boss, and the first to carry **WALL** — the one Counter that needs the arena to answer
back. Almost all of it was already in its old FSM; what the port changed is *what pays*.

| Phase | Beat | Counter kind | Reps | Tail |
|---|---|---|---|---|
| 1 | Charge — a committed rush, a short stalk, then a second dash | bait it into scenery → **WALL** | 1 | 2.0 |
| 2 | Volley — a 4-pellet aimed cone | cross the cone sideways → **UNTOUCHED** | 5 | 0.8 |
| 3 | Blast — one 7-pellet cone, 60° wide, thrown 18 tiles at 7 tiles/s | leave the cone before it arrives → **UNTOUCHED** | 5 | 1.6 |
| 4 | Call — 6 grimlings of three species (90 HP each) | clear the brood → **ADDS** | 1 | 1.6 |
| 5 | Spiral — a 4.8s sweep of 24 unaimed seeds, 27° apart, from its own bearing | read the gap and walk it → **UNTOUCHED** | 2 | 1.2 |
| 6 | Call Big — 3 grimlords, ≤25% HP | burn the long, loud summon → **PUNISH** | 1 | 2.2 |

- **Its ladder IS the Rotation, and its player-paced half becomes the Counter.** The old FSM
  already ran an authored order — rear, call the brood, hunt, charge, wind down — advancing on
  *the player's* pacing: clear the adds, survive the charge. That order is kept, and the pacing
  is spent as Counter credit instead of as a ladder step: clearing the brood is ADDS, putting
  the charge into a wall is WALL, and each credit is what steps M back down. M stays the only
  escalation axis and the ladder is only grammar — the boss does not escalate two ways.
- **The `Rest` states are deleted.** `Winded` (5s), `WindedShort` (3s) and `Brace` (2s) were
  windows with nothing to answer; every burn window is now a beat's own Tail, the same trade
  Fae's and Thornmess's rebuilds made.
- **`Stagger` is deleted as a state and becomes the charge's payoff.** A head-on wall slam used
  to park the boss in a 3.5s rest at ×1.6 and then restart the *whole ladder* from the top, so
  the best the player could do with the knockdown was reset the fight's state. It now ends the
  rush and opens the Phase's Tail, which is where the WALL rollback and its damage both land:
  `Charge.blocked_state` points straight at the Cycle.
- **Its three authored cooldowns (charge 5s, slam 6s, volley 4s) are zeroed** — same reason as
  Thornmess's: a cooling beat is overtaken by the next runnable one and the authored order
  silently drops a Phase. The Rotation is the pacing.
- **The slam is the Reaction, not a Phase.** Gnarlking is the argument that a boss can want the
  player at *both* ends: it charges when you leave and slams when you crowd, and the slam fires
  from the Phase boundary — the Free beat's slot — with `SlamProbe` (3 tiles) deciding. Putting
  it in the Rotation instead would have to choose between a slam lobbed from across the arena
  (a 6-tile pulse landing on nothing: dead time) and a Phase the player can farm; `Slam`
  therefore declares no Counter, and a reaction that whiffs simply does not fire.
- **Its three range probes are kept, and split by what they are for.** `VolleyProbe` (4 tiles)
  keeps the cone from being fired into the void, and `SlamProbe` is what makes *any* PUNISH
  coupling legal — only a beat that ends with the player adjacent can be punished. But a Phase
  the Rotation cannot reach is not a wait, so it hands off to `lost_state` rather than standing
  there: `Close` is the walk (52 px/s, scaled and capped, handing back at the volley's own
  range).
- **`Stalk`'s authored 82 px/s is lowered to 60.** It was already past the 75 cap, so Intensity
  had no dial left to turn on the Hunter's pursuit — the one dial the doc says Gnarlking is
  where it bites.
- **Call Big was already the HP-gated desperation Phase** (`health_max` 0.25). It is now last in
  the Rotation and `priority` + `once`, `Call`'s old `health_min` is dead under a Rotation and
  is gone, and the brood authors `minion_group = &"pack_brood"` with `clear_radius_tiles = 0`
  (exact) so ADDS counts its own summons and nobody else's. The hold is 16s against Thornmess's
  12s — six 90 HP grimlings are more than twice six plants — and still lapses well inside the
  escort's own 22s lifetime, so the rollback is never handed out by a clock.
- **The two ranged Phases are the distance half of the same argument.** Charge answers a player
  who leaves by going and getting them; Blast and Spiral answer one who *stays* out there.
  Blast is aimed and committed — one loud 1.4s tell, a cone that reaches almost the whole arena
  but crawls at 7 tiles/s, so it is read and left rather than dodged on reflex, and eating it
  is the fight's single biggest hit. Spiral is the opposite: `aim_mode = INDEPENDENT`, so it
  ignores the player entirely and paints the floor from its own bearing, 27° per shot so the
  lanes never repeat (the spiralcap's sweep, slowed and shortened for an arena). Neither can be
  out-waited by standing still, which is what stops the Hunter profile from being kiteable.
- **The ranged Phases are the long ones, and that is where the Rep cap moved.** Gnarlking's
  bullet beats are said until the player has actually learnt them — Volley ×5, Blast ×5, Spiral
  ×2 of a 4.8s sweep, each around 10–15s — which is what pushed Reps from 1–4 to 1–8. The summon
  Phases are untouched: an ADDS Phase is already paced by the escort it has to outlive, and a
  second Rep of a summon is a second brood, not a second reading of the same beat.
- **A long Phase makes its UNTOUCHED dearer, on purpose.** The Counter asks for the whole Phase
  clean, so a 12s Volley is a much harder rollback than a 3s one — which is the trade: the
  ranged half of the fight now ratchets M up unless the player really can read it.
- **Blast gates on `DetectProbe` (22 tiles), not a probe of its own** — it is the beat whose
  reach IS the arena, so the only range question it has is whether the boss can see anyone at
  all. Spiral gates on nothing: an unaimed spray has nowhere to be out of range of.
- Profile stays **Hunter**: `Close` and `Stalk` close and stay, and the charge crosses 26 tiles
  at 300 px/s. Distance is answered by pursuit, then by a rush — never by reach.

## Settled during implementation

- The 60s `COMBAT_RESET_SECONDS` leash **does** clear M back to 1.0 with the rest of the fight
  (a rewound fight is a rewound fight). `Creature.reset_combat` calls `BossController.reset`.
- `UNTOUCHED` **counts** damage from the Phase's own adds. It does not matter for Fae (whose
  add Phase is ADDS), and "the player took none" is the clause that needs no special case.
- Fae's per-beat numbers: her two authored casts were left alone, Reps are 2 everywhere except
  the desperation Phase, and the Tails are 1.0–1.4s. The fight's length now comes from the
  Rotation rather than a Rest Phase.
- **Gnarlking's ladder does not compose with M as a second axis; it is the Rotation's order and
  the Counters that brake M** (see its reference instance). This was the port's stated hard call
  and it is settled by making the player-paced half the *answer* rather than the *difficulty*:
  nothing the boss used to ask has been dropped, but clearing the brood or baiting the charge
  now pays a rollback instead of advancing a ladder nothing else could see.
- An ADDS Phase's escort hold **closes the Phase when it resolves at the end of a Phase**, and
  resumes the Rotation when it resolves mid-Phase. Replaying the beat was the same action for
  both, which meant every cleared escort bought the next summon: an ADDS Phase could summon
  forever as long as the player kept killing what it called.

## Open, not yet specified

- **Fae's Sniper switch** (above) — needs a long-range beat and a min-Intensity gate on
  `Behaviour` so a Phase can be eligible only on the second loop.
- **Audio stings** for a step up and a rollback — needs an audio system and assets; the signals
  are already emitted.
- hive queen and Mother are prose only; their scenes do not exist yet.