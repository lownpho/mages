class_name GameConstants

## Tile size in pixels. Bullet stats are authored in tiles; multiply by this to
## convert tiles/sec to px/sec (and tiles to px).
const PX_PER_TILE := 8

## Physics layer bitmasks for bullets (see project settings layer names).
const LAYER_PLAYER_BULLETS := 256
const LAYER_ENEMY_BULLETS := 512
