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
- 4–5 Phases per Rotation. Rough budget: 4–5 Phases × ~2 Reps × ~8s ≈ 100–120s per Rotation,
  so 2–3 minutes is one clean Rotation plus a wrapped second one.

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
  Hunter, is where it will bite.

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
| **ADDS** | the boss's escort group clears | `clear_group` membership |
| **UNTOUCHED** | the player took zero damage across the Phase | the player's `hurt` signal |

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
  Reps, and the pauses (rep gap, Tail, Free beat) in one state. It hands off to a Phase and the
  Phase hands back (`done_state = "Cycle"`). `PatternPicker` (roll) and `Gate` (ordered) stay as
  they are for everything else.
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
  stalls and Fae stays armoured at ×0.25 until they are dead.
- Flit is a `ChargeDashResource` tuned down to Fae's size (150 px/s for 0.7s, 20 contact
  damage, two weak flank bolts) rather than a plain approach, because an UNTOUCHED Counter
  needs a beat that can actually touch you.
- Ring Storm is the HP-gated desperation Phase: last in the Rotation, `priority` + `once`.
- Profile: **Siege** — her ring pulses fill the floor and her wisps hunt you, so backing off
  trades space for adds. The **Sniper** switch at the second loop (a long-range volley) is not
  authored yet; it needs a long-range beat and a min-Intensity gate, and is worth doing when a
  second boss needs the same switch.

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
- **Thormness, then Gnarlking.** Thormmess is a two-resource port. Gnarlking is the hard one:
  its player-paced ladder (clear the brood, dodge the charge) already encodes escalation, and
  how that composes with M — rather than replacing one with the other — is the port's hardest
  call and should be made explicitly.
- hive queen, rotmaw and Mother are prose only; their scenes do not exist yet.