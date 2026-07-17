# Graveyard

Reference-only archive — nothing here is loaded by Godot or the asset pipeline.

Content that the current design (`design/data/*.yaml`) does not make reachable gets moved
here instead of deleted: enemies outside every biome roster, spells nothing drops, behaviour
scripts no scene uses, and orphaned art, together with their `asset_src/` `.ase` sources.
Paths mirror the original tree (`graveyard/game/...`, `graveyard/asset_src/...`), so a file
can be revived with a `git mv` back to its old location (re-check `res://` refs and uids
after reviving — anything referencing content that changed since archival may need fixing).
