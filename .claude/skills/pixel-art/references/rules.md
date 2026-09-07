# Pixel Art Technical Rules

The grammar applied during the critique step. The validator cannot check most of
these — they require looking at the rendered image.

## 1. Line stepping (jaggies)
Diagonal and curved lines must use consistent step lengths. A line going
2,2,2 then suddenly 1,3 reads as broken. Pick a step rhythm and hold it.
At 8×8 most diagonals are 1:1 steps; keep them perfectly regular.

## 2. Doubles
A 1px line that accidentally becomes 2px wide for one step looks like a blob.
When tracing any line, check its width is constant.

## 3. Curves
Pixel circles use fixed quarter-arc forms. 8px circle row widths from top:
2, 1, 1 (then mirror). Flat segments shrink as the curve turns. Never place
a step longer than the one before it when curving inward.

## 4. Shading (within the two-flat-tones rule)
- One light source, top-left by convention. The shadow tone sits on the far side.
- **No pillow shading**: bright center ringed by dark = broken.
- **No banding**: a shadow band running exactly parallel to the silhouette edge
  flattens the form. Break it by shifting it 1px somewhere along its length.
- Pick the shadow as a **hue-shifted** darker Zughy entry (toward blue/purple),
  not just the nearest darker gray — pure darkened-base shadows look muddy.

## 5. Orphans
No isolated single pixels unless they are deliberate (an eye, a sparkle).
The validator flags all of them; you decide which are intentional.

A second, sneakier form only shows up in animation: a pixel that isn't a true
orphan (it touches other non-transparent pixels, just not of its own color)
but is *new* — absent from the idle frame — and unconnected to any same-color
patch. That reads as a stray fleck stuck to the body, not a body detail: a
lone red spark on an attack windup looks exactly like a bullet fragment; a
lone near-black pixel widened for a "cracking open" telegraph can read as a
punched-through hole rather than a shadow. It's specific to non-idle frames
because idle is usually modeled closely on an established sibling sprite,
while action frames are where new accents get added without that anchor.
`validate.validate_animation` checks for this (compares every frame against
frame 0) — run it before finalizing any attack/action animation, not just
the single-grid orphan check.

## 6. Readability at 8×8
- Silhouette first: the sprite must read as its subject in solid black.
- 1px = a feature. One bright pixel is an eye. Two columns are legs.
- Maximum contrast at the focal point (face/eyes), lower elsewhere.
- 3–4 colors total; 5+ turns to noise at this size.

## 7. Animation
- Pivot stability: the sprite's anchor (usually feet line or center of mass)
  must not slide between frames unless motion demands it.
- Move the minimum: a 2-frame walk = legs swap + optional 1px body bob.
  Head/torso stay pixel-identical (enforce via static parts).
- Silhouette continuity: frame N and N+1 silhouettes should overlap heavily;
  use the onion-skin render to verify only intended pixels moved.
- Timing: 2–3 frames at 6–8 fps reads as a lively walk at 8×8. Idle bobs
  are fine at 2 frames / 2–3 fps (idle rows ship at ≤5 fps).
- Secondary motion (tail, ears) reads better 1 frame delayed from the body.
