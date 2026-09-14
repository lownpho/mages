---
name: creature-sprite
description: >
  Design and animate an enemy/creature/monster/boss sprite — the ART and its
  per-state animations, not the scene wiring. Use when the user wants to
  create, draw, or animate a creature/enemy/monster/beast/boss, give an
  existing enemy new animations, recolour a variant, or asks for a specific
  read (front-facing, coiled, armoured, disguised). Covers the creature
  design grammar (silhouette families, recolour variants, mimicry, eyes),
  how animation tags map to the enemy's FSM beats, and the
  attack-reads-as-motion rule. Rides on the pixel-art skill for the
  render/view/iterate loop and .ase export; hands off to add-enemy for the
  scene/data/spell wiring.
---

# Creature sprites

The design grammar for **living things** — the 52-strong hostile roster and the player's
summoned minions. A creature is not a scenery prop and not a UI icon: it has a face, it is read
as a threat at a glance, and it **animates across the beats of its FSM**.

This skill rides on two others — read them first, don't duplicate them:

- **`pixel-art`** — the non-negotiable style doctrine (Zughy 32 only, flat tones, no world-sprite
  outlines, silhouette-first, eyes as the focal point), the frame tiers, the
  render→*view the PNG*→critique→iterate loop, `references/rules.md`, and the whole `.ase`
  export pipeline (`import_multi_tag.lua`, `verify_export.sh`). Use its scripts (`render.py`,
  `inspect_sheet.py`, `animation.py`, `validate.py`) — do not hand-roll them.
- **`add-enemy`** — turning the finished sheet into a working enemy: the composed-from-the-
  behaviour-library scene, the `CreatureResource`, the cast `.tres`, `.png.import`, uids,
  roster placement.

This skill is the middle layer: **what a creature should look like, and which frames it needs so
its beats can play them.**

`design/docs/enemies.md` carries an **Art:** line for every shipped creature, straight from
`design/data/enemies.yaml`. Read the neighbours' lines before drawing — they are the roster's
own statement of its grammar, and your new creature owes the same line.

---

## 1. The silhouette families

The roster is not 52 independent designs. It is a **small set of silhouettes, recoloured and
re-proportioned**, which is what makes a biome read as a family and a rare read as "that thing,
but worse". Before you invent a shape, check whether the creature is a member of one:

| Family | Base | Variants |
| --- | --- | --- |
| Snake | a low serpentine coil, forked head, one bright eye pixel | `coral_snake` (hot coral, banded), `ash_snake` (ashen, cyan eyes), `viper`, `adder` (charcoal + amber) |
| Grimling | a small hunched shadow-sprite, needle limbs, amber eye-glow | `shard_grimling` (plum, duller glow), `wisp_grimling` (pale, brightest glow), `grimlord` (enlarged, near-black, red glow) |
| Golem | the golem block | `dirt_golem` (packed earth + grass tufts), `moss_golem` (moss over stone), `mould_golem` (fungal white) |
| Moth | dusty rounded wings, two pale eye pixels | `moon_moth` (moonlit), `needle_moth` (rust) |
| Owl | a brown oval, oversized head, two big amber eyes | `great_owl` (enlarged, barn-owl white) |
| Back | a wide squat body, armour over a spike array | `thornback` (dark brown), `razorback` (near-black, red tips) |
| Shade | a wispy near-black silhouette, pale eyes | `umbra` (deeper black, thin red edge) |
| Cap | a squat mushroom body | the whole mycelium roster |

**A variant is a recolour plus one silhouette tell, not a redraw.** The eye is the loudest half
of it: wolfish yellow → orange, amber → red, duller → brighter as the thing gets rarer. Copy the
sibling's grid with `inspect_sheet.py`, change the palette dict, change one or two cells, and you
are done — that is how most of the roster was made and it is the fastest correct path.

### Mimics reuse the scenery sprite

Several enemies are **the biome's own decor with eyes**: `bramble_stalker` is built from the
deepwood decor bush (same three greens), `cinderstone` is the boulder the deepwood scatters
everywhere with one hairline crack, `elder_stalker` is a dead-tree disguise, `puffcap` is a cap
you'd walk past. When the brief is "an ambusher", the right move is to pull the actual scenery
sheet with `inspect_sheet.py` and start from those exact pixels — the disguise only works if it
is pixel-honest, and the reveal frame is where the eyes arrive.

### When it is genuinely new

Default to the **front-facing bust**: the camera-facing body with the head dominant, two eyes,
a hint of limbs and feet. It fits the tile, reads instantly, and flips cleanly left/right. The
non-bust silhouettes in the roster all earn it — a serpentine coil that is read from above, a
squat armoured back seen from behind-above, a rooted plant with no legs at all. Pick one read and
hold it across the creature's whole sheet; a sprite that changes viewpoint between idle and
attack reads as two creatures.

**Frame size obeys `pixel-art`'s tier doctrine, and the roster obeys it hard**: 47 of the 55
shipped sheets are **8×8** frames, five are 16×16 (`fae`, `thornmess`, and the big variants),
two are 8×16, and exactly one — the `gnarlking` — is 16×24. Being the heavy sibling of another
enemy is **not** a licence to grow the frame: `razorback` is `thornback`'s size, `grimlord` is a
grimling's, and both read as bigger threats through colour and build alone. Step a tier only for
a genuine boss, and when unsure, ask.

---

## 2. The animation set = the creature's beats

An enemy's sheet has **one row (Aseprite tag) per animation a beat will `play()`**. The tag name
**must exactly equal** the string the beat plays, or the creature freezes on its current frame
(`Creature.play()` silently pauses on a missing anim).

**The names are not a fixed vocabulary — they are whatever the scene's exports say.** Every beat
in the behaviour library names its own animation:

| Export | On | Default |
| --- | --- | --- |
| `anim` | `Hold`, `Wander` | `"idle"` |
| `anim` | `Approach` | `"run"` |
| `attack_anim` | `Cast`, `Charge` | `"attack"` |
| `windup_anim` | `Cast`, `Charge` | `""` (holds the current pose) |
| `run_anim` | `Flee` | `"run"` |
| `fly_anim` | `Tether` | `"fly"` |

So the floor is **`idle`** (always), plus **`run`** for anything that moves and **`attack`** for
anything that fires — that covers a plain chaser, and a rooted turret like the `sproutling` needs
only `idle`/`attack`. Everything past that is the creature's own vocabulary, and the roster uses
it freely: `pop`, `charge`, `rest`, `windup`, `root`, `crouch`, `summon`, `blink`, `wake`,
`swell`, `shell`, `reveal`, `recover`, `guard`, `fuse`, `dive`, `detonate`, `dash`, `burrow`,
`surface`, `stun`, `spores`, `slam`, `inhale`, `erupt`, `enrage`.

**Derive the list from the scene, not from a table.** Decide (or read) the beats first, list the
`anim`/`windup_anim`/`attack_anim` strings they'll carry, and design exactly to that list. A
separate `windup_anim` is what buys a telegraphed attack its wind-up pose; a boss with a Gate
rotation may want a distinct tag per rung so each beat reads differently.

Every animation is **2–4 frames** (`pixel-art` §Animation / rules.md §7). In the shipped scenes
the `SpriteFrames` sub-resource lives in the `.tscn`, `idle` loops at ~2 fps and action rows run
~4–8 fps and usually don't loop.

**The idle is the most important frame** — it is the bestiary portrait and the first thing the
player meets; the creature must be alive standing still (a leaf twitch, a breathe, a hackle
bristle).

---

## 3. Attacks read as body motion — never spawn art in the sprite

The single creature-specific rule that trips people up (a sharper form of rules.md §5):

**An attack frame conveys the strike through the body — a lunge, a rear-up, a shell hunch, a
thorn bristle, a forward thrust. It must NOT add a mouth, a hole, or a projectile to the
sprite.** Bullets are separate entities spawned by the cast; drawing one on the creature reads as
a stray fleck, and a new dark opening reads as a punched hole. Keep the silhouette continuous
with idle; move the whole mass, don't carve a new feature into it.

Corollary — **the muzzle trap.** A dark nose or mouth *enclosed* by a lighter face on all sides
reads as an open, screaming mouth. Put the dark pixel at the **bottom edge** of the light area
with dark body or nothing below it. A snout, beak or maw is a permanent, unchanging feature
across idle/run/attack — unless the creature's whole point is that it opens (`thornmess`'s
screaming maw), in which case it is open in every frame, not carved in on the attack.

`validate.validate_animation(frames, ...)` catches this mechanically: it flags isolated **new**
pixels versus frame 0.

---

## 4. Colour & eyes (creature specifics on top of pixel-art)

- **Zughy 32 only — never invent a shade.** The failure mode is needing a "dark grey" for
  shadow and inventing one a few points off. Every grey you need is already there:
  `#302C2E` black, `#5A5353` dark, `#7D7071` mid, `#A0938E` light, `#CFC6B8` silver,
  `#DFF6F5` white. In-game they have names in `game/globals/palette.gd` (`Palette.GREY_DARK`,
  …) — the same list, so a sprite colour and a telegraph colour can be the same constant. Pick
  the shadow from an existing entry, hue-shifted darker (rules.md §4).
- **Eyes are identity and the brightest pixels on the body** — amber `#F4B41B` / orange
  `#F47E1B` for beasts and grimlings, cyan `#8AEBF1` / `#28CCDF` for spectral things, white
  `#DFF6F5` for the enraged. A rarer or meaner variant of the same creature shifts eye colour
  and value, not just size.
- **The eye colour is also the creature's telegraph colour.** `add-enemy` sets a Cast beat's
  `telegraph_color` from `Palette`, usually the eye's hue, so the flash says both "incoming" and
  "from what". Choose the eye knowing it will flash the whole body later.
- **A shared sub-palette per family** keeps a biome coherent: sample siblings with `pixel-art`'s
  `inspect_sheet.py` before drawing, exactly as `biome-scenery` samples the floor.
- **No eyes at all is a legitimate design** for something pretending not to be alive
  (`puffcap`). It is the exception that proves the rule — and it needs a compensating tell.

---

## Workflow

1. **Place it in a family** (§1) — is this a recolour of a shipped sibling, a mimic of a scenery
   prop, or genuinely new? Dump the closest existing sheet with `inspect_sheet.py` and start from
   those pixels. Read the neighbours' **Art:** lines in `design/docs/enemies.md`.
2. **List the frames from the beats** (§2) — decide the FSM (or read the target scene) and derive
   exactly which tags you owe from the `anim`/`windup_anim`/`attack_anim`/`run_anim` exports.
   Design *to that list*.
3. **Draw + animate through `pixel-art`** — grid → `render_grid` → **view the PNG** → critique →
   iterate (minimum two cycles per animation); `validate_animation` every action row (catches the
   stray-new-pixel / §3 violation); keep the attack body-motion only.
4. **Export** with `pixel-art`'s multi-tag pipeline — one tag per row, tag names = the `play()`
   strings from step 2 — and prove the round-trip with `verify_export.sh`. Creature art lives at
   `asset_src/graphics/characters/enemies/<id>/<id>.ase` → `game/characters/enemies/<id>/<id>.png`.
5. **Wire it** — hand off to **`add-enemy`** for the `.tscn` (the `SpriteFrames` sub-resource,
   one entry per tag), the `CreatureResource` (health/rarity/kinds/drops, and the `icon`
   AtlasTexture pointing at the **idle frame at native size**), the cast `.tres`, the
   `.png.import` and the roster placement. Set each firing beat's `attack_anim` if it isn't
   the default `"attack"`.
6. **Write the Art: line** into `design/data/enemies.yaml` alongside the rest of the enemy's
   entry, then rebuild:
   `design/tools/.venv/bin/python design/tools/build.py`.

## Validate

`pixel-art`'s view-the-render and `validate_animation` checks are the art gate — no mechanical
check tells you whether it reads as a threat, only looking does.

For the assembled enemy, `godot --headless --path game res://tests/test_enemy_scenes.tscn`
confirms every scene loads with an icon and hp. Note two silent failures it can't catch: an
animation tag that doesn't match a beat's `play()` string leaves the creature **frozen** rather
than erroring, and a zero-output headless timeout is a **GDScript parse error**, not slowness.
Then look at it moving in the World (`godot --path game res://scenes/world.tscn`, which writes the
Run save; **Tab**, Combat tab, click to place it, watch every beat fire) — and at its portrait in the bestiary, which is where the idle frame gets
judged.
