class_name GameConstants

## Tile size in pixels. Bullet stats are authored in tiles; multiply by this to
## convert tiles/sec to px/sec (and tiles to px).
const PX_PER_TILE := 8

## Physics layer bitmasks for bullets (see project settings layer names).
const LAYER_PLAYER_BULLETS := 256
const LAYER_ENEMY_BULLETS := 512

## Canvas z ladder (world space), authored in the editor: each scene carries
## its value as a literal, and these constants are the reference list — keep
## them in sync. Gaps of 10 leave room for new layers. Default z 0 (no
## explicit index) is features, enemies, and bullets; the UI lives on its own
## CanvasLayer and doesn't use this ladder.
const Z_GROUND := -20  # world.tscn ground TileMapLayer
const Z_GROUND_EFFECTS := -10  # ground decals: brrr.tscn Patch, kaboom_meteor.tscn Mark
const Z_PICKUPS := 10  # items/pickup_item.tscn root
const Z_PLAYER := 20  # characters/player/player.tscn root
const Z_OVERHEAD := 30  # effects floating above characters: nope.tscn root
