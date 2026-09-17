# Mages World

The shared language for Mages' generated world, its progression, encounters, and discovery.

## World structure

**World**:
The one finite, seamless area generated for a Run. Its room graph contains every Biome and is planned before play, while room interiors and tiles stream around the player.
_Avoid_: Space, overworld

**Ideal path**:
The intended route through Glade, Deepwood, Wastelands, and Fruit, in that order. It guides challenge and placement without preventing the player from leaving it.
_Avoid_: Main path, critical path

**Biome**:
A contiguous part of the World with its own Zones, presentation, room-shaping values, content, and Boss.

**Side biome**:
A Biome outside the Ideal path that attaches as a dead end directly to one Room on its parent Biome's Ideal path. Hive and Mycelium belong to Deepwood; Moon and Hell belong to Wastelands, and their attachment positions vary by seed.
_Avoid_: Branch, Dungeon

**Side route**:
The intended route from a Side biome's attachment to its Boss. Its challenge rises independently and does not alter the Ideal path.

**Zone**:
A contiguous subdivision of a Biome that adds its own content to the Biome's shared content. Its order is generated rather than authored.

**Spawn zone**:
The Glade Zone containing the player's initial spawn. It is always the first Zone on the Ideal path.

**Room**:
A discrete walkable area bounded by shared walls and joined to neighbouring Rooms by Passages.

**Passage**:
A walkable connection shared by two Rooms.

**Shortcut**:
An optional Passage outside the Ideal path that shortens traversal without being locked or guarded against.

## Progression and encounters

**Challenge**:
An integer describing expected encounter difficulty at a place in the World.

**Entry challenge**:
The lowest Challenge at which an enemy becomes eligible for ordinary encounters in a roster.

**Roster**:
The enemies eligible for generated encounters and Hazards in a Biome or Zone, together with their Entry challenges.

**Hazard**:
A stationary roster enemy, such as a mine, spread on its own across a Room's floor instead of joining an Encounter.
_Avoid_: Filler, mine, trap

**Encounter**:
A generated group of enemies met as one fight.

**Fixed encounter**:
An authored leader and escorts belonging to a Rare, Miniboss, or Boss.

**Teaching room**:
A Room that introduces a newly eligible enemy in every encounter while dipping the other encounter content below the local Challenge. Hazards are never introduced this way.

**Testing room**:
An ordinary combat Room populated from its roster at the local Challenge.

**Breather**:
A Room with no encounters that may hold one or more Objects.

**Set-piece room**:
A guaranteed spacious Room reserved for a Boss, Miniboss, or Rare and never used for Objects.

**Rare**:
An optional, seed-varying Fixed encounter in a Set-piece room.

**Miniboss**:
An authored optional Fixed encounter in a Set-piece room, usually placed late in a Zone.

**Boss**:
A Biome's authored optional Fixed encounter in a Set-piece room near the end of its Ideal path or Side route.

## Objects and discovery

**Object**:
An interactive or reactive world entity placed in a Breather, except where its kind defines another location.

**Sign**:
An Object with authored text, placed once, that may reveal a Boss or Miniboss on the Map.

**Professor**:
An interactive Object that reads the Bestiary page of the Biome it stands in and pays out when that
page is complete. A portal Professor opens a Portal onward; an item Professor gives up one of the
things that drop there. It pays out once a Run, and says what it sees either way.

**Portal**:
The way onward a portal Professor opens beside itself, leading into the Biome onward exactly as a
Warp door leads into its destination.

**Biome onward**:
The Biome a Professor's reward points at: the next on the Ideal path, or for a Side biome, the one
after its parent. A sealed Biome is none, and a Professor with none gives nothing.

**Warp door**:
A seeded one-way Object that skips to the previous or next Ideal-path Biome, or from a Side biome back to its parent. It stands in a Breather and lands at a cleared spot in an ordinary Room rather than requiring another Warp door.

**Map**:
The persistent record of discovered Rooms, Pins, and revealed places in the World.

**Pin**:
A player-created marker on a free tile of the Map, without a label or type.

**Run**:
One attempt through a generated World. Quit/Continue preserves it; death ends it and discards the World, Map, and other run state, while only the Bestiary and Grimoire persist between Runs.
