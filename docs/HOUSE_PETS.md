# House pets (Phase 3c, core)

Pets are appearance only; no pet command controls a device. Part 1 supplies the
core and command interfaces. The SwiftUI overlay and editor belong to part 2.

## Storage and synchronization

Each `HomeHouse` optionally has `pets: [String: HousePet]` and `petPrefs`.
Keys/IDs are `p_` plus 4–6 hexadecimal digits. A pet has `name`, `species` (`cat`),
`rig` (`cat-short`), `pattern`, `palette` (`base`, `second`, `white`, `eye`, each
`#RRGGBB`), `enabled` (default true), `homeRoom` (null/absent means roaming),
`updatedAt`, and `deleted` (default false). Missing fields decode to defaults;
old schema-1 files remain compatible. Preferences have `enabled` (default true)
and `updatedAt`. `HouseFile.setPet(home:pet:)` validates additions/updates and
rejects a fourth non-deleted pet. Disable does not free a slot; remove does.

Merge is independently last-write-wins per pet ID and for preferences. Removal
writes a dated tombstone, which is retained so an offline Mac cannot resurrect
the pet. Concurrent independent additions may merge above three; merge preserves
records rather than silently deleting a pet. Explicit local additions remain
limited to three. No photo path, photo bytes, or mask is stored in house.json.

## Rig and encoded sheets

`HousePetRig.load(from:)` loads and validates `cat-short.json`. `frameSize` and
`anchor` use cells; `cellPx` is the pixel scaling factor. Sheet frames are row-major
by `columns`. Actions define `fps`, `loop`, and frame lists for SE/NE; `mirror`
maps SW to SE and NW to NE. `frame(action:facing:elapsed:)` returns the rig index
and mirror flag. Flip around `anchor`, **not** the image center. Scale with nearest
neighbor and never interpolate. Output frames remain at cell resolution.

`HousePetSheet.load(from:)` uses ImageIO then reads the CGImage data provider,
honoring byte order, row stride, and alpha placement. Unsupported/premultiplied
layouts are rejected rather than silently corrupting encoded data. Encoded sheets
are never drawn into a CGContext. Alpha zero is empty; partial alpha is a shadow;
opaque pixels encode region/outline in R, shade in G, and specular intensity in B.

For normalized palette colors, the region table is:
`1=base, 2=second, 3=white, 4=base*.7+(1,.95,.88)*.3, 5=(.93,.60,.64),
6=eye, 7=(.09,.07,.09), 8=(1,1,1), 9=11=base*.30+(.08,.05,.06)*.7`.
Let `r=R&15`, `outline=(R>>4)&1`, `s=G/127.5`, `k=B/255`.

```
tsh = clamp((.85-s)/.6, 0, 1)
thi = clamp((s-1)/.4, 0, 1)
tint = 1 + tsh*((.86,.89,1.10)-1)*.7 + thi*((1.05,1.02,.95)-1)
colour = table[r]*s*tint + k*(1,.97,.92)
if r in {6,7,8,9}: colour = table[r]
if outline: colour = (table[r]*.42*(.92,.88,.95)+(.07,.04,.05))*.75
colour = clamp(clamp(colour)*lighting.mul + lighting.add)
```

Partial alpha instead returns straight RGB `(.12,.08,.07)` with the original
alpha and **no lighting**. Alpha zero returns transparent black. Channels round
to bytes. Golden vectors in `Tests/Fixtures/pets/cat-short-golden.json` allow ±2.
`HousePetFrameCache.frames(pet:rig:directory:phase:)` caches all frames by rig,
directory, pattern, palette and lighting (day/dayLit/night/nightLit), with bounded
entries and a lock. Reuse a cache instance; call `clear()` on resource reload.

## Photo palette and privacy

`HousePetPhoto.analyze(rgba:width:height:mask:eye:species:)` is deterministic pure
Swift: at most about 16k samples, sRGB→CIELab, farthest-point seeding, k=5,
16 Lloyd iterations. Cluster areas and Lab hue/lightness pick the coat colors.
Dark same-hue patches above 8% imply tabby; white above 12% adds white;
orange + dark + white implies calico; cream with spatially dark extremities
implies colorpoint. Other two-color white coats are bicolor; otherwise solid.
Small saturation/brightness lifts avoid muddy photo colors. Orange/brown coats
default to green eyes, neutral coats amber, colorpoints blue; an eye override wins.
Confidence is a heuristic cluster-quality score, not a species-model probability.

`HousePetPhoto.load(from:eye:recognizeSpecies:)` reads a local file through
ImageIO, applies EXIF orientation, downsizes to at most 512px, and optionally runs
Vision animal recognition (cat/dog/unknown). `HousePetForeground.mask(image:)`
uses macOS 14 foreground instance segmentation where it succeeds, otherwise
a center-weighted ellipse. The reusable mask is one byte per pixel, >127 selects
foreground. Pure analysis without a mask uses all nontransparent pixels.
Only cats are currently instantiated, even when the photo reports dog/unknown.

**Photos are never stored, copied to disk, cached, or uploaded.** All analysis and
Vision requests run locally in memory; only the palette and pattern persist.
The user-supplied source file is neither modified nor removed. `add --photo`
returns the detected palette/pattern/species/confidence alongside the saved pet.

## World and behavior

`HousePetSpots.load(from:)` reads `pet-spots.json`: style→art-set map, module
walk grids, spots and optional perch approach cells. Each floor grid unit has
`cellsPerGrid` cells (currently 8). Cell centers have
`u=(col+.5)/8, v=(row+.5)/8`. Module pixels are
`tip + (160*(u-v),66*(u+v)-z)`. `HousePetWorld` applies catalog tips, layout
placement and `HouseLevels` elevations. Pass `origin` from the compose result
to share its canvas coordinates, or pass exact per-room top-left `offsets`
(already including origin/elevation). No rendering or module images are needed.

Four-neighbor walk edges stay inside modules. Shared layout borders connect
facing walkable cells across the cut wall (allowing the one-cell blocked wall
rim); differences ≤48px are jumps, 96px differences are blocked. A* caches paths;
`path(from:to:room:allowedRooms:)` optionally confines the whole route to a room
or a set of existing rooms. Decor with
`petSpot=true` supplies preferred sleep spots by its resolved slot, projected to
the nearest walk node. Bed/sofa perches rank next, then sleep spots and a room
fallback. Catalog light `pool` centers provide lookup/sit reaction destinations.

Keep one `HousePetBehavior(rig:)` instance. `pose(_:world:context:at:)` is a pure
function of these inputs despite internal plan/path memoization. Stable FNV/LCG
seeding uses the local calendar day and pet ID, never Swift randomized hashes.
The cached day plan alternates 8–60s rest activities and A* movement at 36px/s.
Cross-module/perch jumps last .5s; `jumpLift` is a positive parabolic displacement
to subtract from screen y. +u faces SE, -u NW, +v SW, -v NE.

Supply `HousePetContext` with existing room keys, active pet IDs, per-room lights,
TV room keys, night state and `changedAt`/`changedRoom`. Keep the same timestamp
until the next context change. Reactions begin from the baseline plan at that
timestamp: dark night seeks sleep; TV seeks its TV spot; a light change produces
2s lookup then a light-pool sit. `homeRoom` confines routes and rest locations.
Sorted pet IDs partition separated rest spots; pass the **same roster** to every
pet. `restOnly=true` chooses the current/next rest spot and restricts actions to
idle/sit/sleep, without changing the underlying full-scene day plan. `visible`
also reflects pet/global enablement and missing-room safety.

## CLI and MCP

```
mijiabar house pets list --json
mijiabar house pets add --name Mochi --photo /local/cat.jpg
mijiabar house pets add --pattern tabby --palette 'base=#E8973F,eye=#9CC43E'
mijiabar house pets set p_a1b2 --room ROOM_KEY --enabled true
mijiabar house pets set Mochi --room auto
mijiabar house pets preview Mochi --out /tmp/pet.png --action sit --phase night
mijiabar house pets remove p_a1b2
mijiabar house pets off
mijiabar house pets on
```

`pet` aliases `pets`; `--home H` selects a home. Pet selectors accept an exact ID
or an unambiguous name. `set` accepts all appearance flags, including a new local
photo. `preview` writes a nearest-neighbor recolored PNG contact sheet, not a GUI.
Palette flags may specify a subset of the four colors. `--room auto` clears the
room restriction. Lists and all mutations return JSON.

MCP `get_house_pets` returns pets, preferences, patterns/actions and `limit:3`.
`set_house_pets` accepts `op:add|update|remove|enable|disable`, `pet` (ID/name for
update/remove), optional home/name/pattern/palette/room/enabled, and `photoPath`
for add only. Room null clears the restriction. Both descriptions state:
“Appearance only, never controls devices.” Like decor, these use the house
appearance policy (agent interface must be enabled), not device-write permission.

## Part 2 integration and art

Load rig/spots/sheets using app `AppResources`, never an implicit package bundle
accessor. CLI uses the same root search as `HouseDecorFiles.roots`. Use
`HouseFile.setPet`/`setPetPrefs` inside `HouseStore.update` for persistence. Keep
`HousePetFrameCache`, `HousePetWorld`, and `HousePetBehavior` alive between ticks;
rebuild the world on layout/style/decor changes. Position the frame by its anchor,
apply mirror and jump lift, and use the matching phase's frame cache. Menu embeds
set `restOnly`; Reduce Motion may also use that mode. No SwiftUI changes or
snapshot flags are included in part 1.

Art regeneration belongs to `scripts/house_pets/` (added later by the art pipeline).
Do not hand-edit encoded sheets or spot assets. After regenerating, run the
golden, grid, sheet and resource tests. Run `swift build` and `scripts/test.sh`;
unit tests must not launch the app or any GUI.
