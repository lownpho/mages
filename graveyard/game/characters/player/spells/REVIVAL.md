# Reviving a graveyarded spell

`git mv` the spell folder back under `game/characters/player/spells/`, re-scan
the YARD registries, and wire a drop. Most spells need nothing more.

These four relied on **engine hooks that were pruned** from the live caster once
they left the roster (they added dead branches with no shipped user). Reviving
one means restoring its hook first:

- **shing** — the cast echo. Restore `arm_echo()` / `_echo_active` /
  `_schedule_echo()` on `SpellCaster` and the echo branch in `_spawn_effect()`.
  Shing's effect calls `caster.arm_echo()`.
- **kaboom** — `effect_at_cast_start` on `SpellResource`. Restore the field and
  the two branches in `SpellCaster._try_cast` / `_on_cast_time_finished` that
  spawn the effect at cast start and skip the resolve-time spawn.
- **bwoom**, **vroop** — `channel_while_moving` on `SpellResource`. Restore the
  field and the `if not spell.channel_while_moving:` guards around the Cast/Idle
  FSM transitions in `SpellCaster` (channel branch and `_end_channel`).

See git history of `spell_caster.gd` / `spell_resource.gd` for the exact code.
`charge_dash` also depended on `Player.start_dash` suspending (not cancelling) a
live burst — that path still exists, but the `burst_window` that bounded a
suspended burst was removed; re-add it to `WeaponSpellResource` if a revived
dash makes long suspensions possible again.
