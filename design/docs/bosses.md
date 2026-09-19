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
One playthrough of a Phase's beat. Reps of a Phase are identical. 1–4, authored per Phase,
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
- 3–5 Phases per Rotation. Everything else about the Rotation is the boss's own grammar, not
  a shared template: Reps run 1–4, Tails 0.5–2.5s, and the length falls out per boss rather
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
  and no boss repeats its predecessor's mix. Counter kind is coupled to range — only a beat
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
- A boss may author **one switch**, engaged at the second loop (M ≥ ~1.6), so the escalation
  can read as *the boss changed its answer to you*, not just faster numbers.
- Assignments: Fae **Siege → Sniper** (the Siege half is shipped; the Sniper half is not
  authored yet — see the reference instance), Thornmess **Siege**, Gnarlking **Hunter**,
  hive queen **Siege → Sniper**, rotmaw **Hunter** (via burrow), Mother **Sniper**.

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

## Settled during implementation

- The 60s `COMBAT_RESET_SECONDS` leash **does** clear M back to 1.0 with the rest of the fight
  (a rewound fight is a rewound fight). `Creature.reset_combat` calls `BossController.reset`.
- `UNTOUCHED` **counts** damage from the Phase's own adds. It does not matter for Fae (whose
  add Phase is ADDS), and "the player took none" is the clause that needs no special case.
- Fae's per-beat numbers: her two authored casts were left alone, Reps are 2 everywhere except
  the desperation Phase, and the Tails are 1.0–1.4s. The fight's length now comes from the
  Rotation rather than a Rest Phase.

## Open, not yet specified

- **Fae's Sniper switch** (above) — needs a long-range beat and a min-Intensity gate on
  `Behaviour` so a Phase can be eligible only on the second loop.
- **Audio stings** for a step up and a rollback — needs an audio system and assets; the signals
  are already emitted.
- **Gnarlking, and WALL with it.** Thornmess is specified above; it deliberately carries no
  charge. Gnarlking is the hard one: its player-paced ladder (clear the brood, dodge the charge)
  already encodes escalation, and how that composes with M — rather than replacing one with the
  other — is the port's hardest call and should be made explicitly. It is also the first boss
  that should carry **WALL**, since a charge the player baits into scenery is what its ladder
  already asks for.
- hive queen, rotmaw and Mother are prose only; their scenes do not exist yet.