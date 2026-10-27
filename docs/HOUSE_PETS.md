# House pets (Phase 3c)

Pets are appearance only; neither the overlay nor pet commands control a device.
The core, CLI/MCP, SwiftUI overlay, editor and synthetic snapshot exporter share
the same rig, palette analysis, world and behavior implementation.

## Storage and synchronization

Each `HomeHouse` optionally has `pets: [String: HousePet]` and `petPrefs`.
Keys/IDs are `p_` plus 4–6 hexadecimal digits. A pet has `name`, `species` (`cat` or `dog`),
`rig` (`cat-short` or `dog-short`, matching the species), `pattern`, `palette` (`base`, `second`, `white`, `eye`, each
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

`HousePetRig.load(from:)` loads and validates `cat-short.json` or `dog-short.json`. `frameSize` and
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
to bytes. Golden vectors in `Tests/Fixtures/pets/{cat,dog}-short-golden.json` allow ±2.
`HousePetFrameCache.frames(pet:rig:directory:phase:)` caches all frames by rig,
directory, pattern, palette and lighting (day/dayLit/night/nightLit), with bounded
entries and a lock. Reuse a cache instance; call `clear()` on resource reload.

The app lights cached day frames using the room phase (or the sampled lit/unlit
ratio at night). Only at night, very dark opaque coat regions receive a gentle
blue-grey floor and a low-strength, one-pixel cool rim inside the top/side
silhouette edges. Strength fades with the original coat luminance, leaving light
coats nearly unchanged; iris regions retain a little more of their original
colour. Region masks are cached, with no blur, halo, or added silhouette pixels.
Day/dayLit bytes are unchanged. Partial-alpha ground shadows still receive only
the existing night shadow multiplier, even in lit rooms.

### Dog template

`dog-short` is one compact domestic dog with a longer muzzle, black nose, erect
ears, thick chest, short sturdy legs and curled tail, not an additional cat breed.
It uses the cat encoding, region table and identical lighting block. Each rig has
68 authored frames across SE/NE, with SW/NW mirrored around the foot anchor.
Both expose idle (4 fps), walk (8), sit (3), groom (4), lookup (3), sleep (2),
stretch (4, non-looping) and jump (8, non-looping). Sleep stays curled, with
closed eyes; every facing/pattern meets the ≥85% sit-width and sit-height gate.

The six stable pattern IDs are shared, but dog paint is part-local and distinct:

| ID | Dog coat mapping |
| --- | --- |
| `solid` | Single coat with a lighter muzzle/bib |
| `tabby` | Brindle-like irregular body stripes and darker ears/mask |
| `tabbyWhite` | Brindle with white chest, blaze, socks and tail tip |
| `bicolor` | Base coat with white muzzle, blaze, bib and socks |
| `calico` | Tricolor saddle/cap, base-colored cheeks and white markings |
| `colorpoint` | Dark extremities, ears, tail tip and muzzle mask |

The editor retains the shared pattern labels for compatibility. Floppy ears,
breed-specific proportions and additional dog breeds remain future art work;
second/long-haired cat templates are explicitly deferred. No cat sheet or golden
fixture is regenerated for this addition.

## Photo palette and privacy

`HousePetPhoto.analyze(rgba:width:height:mask:eye:species:eyeSamples:extremities:)` is deterministic pure
Swift: at most about 16k samples, sRGB→CIELab, farthest-point seeding, k=5,
16 Lloyd iterations. Before clustering, the brightest low-chroma foreground
pixels (up to 6% of the mask, at least 3%) estimate white balance toward
(0.95, 0.93, 0.90), with gains clamped to 0.75…1.6. Lab fractions classify white
(L>70, chroma<16), dark (L<30), warm (chroma>20, hue 35°…85°, 35<L<85),
and neutral grey (chroma<12, L=30…70). Classification, in order:
white≥12% + warm≥7% + dark≥5% → calico; cream≥45% with dark extremities →
colorpoint; white≥15% → tabby & white or bicolor; otherwise tabby or solid.
A darker same-hue cluster covering ≥10% of non-white coat, or high local
luminance variance, indicates stripes. Colorpoint extremities use pose joints
when available, otherwise an edge heuristic relative to the foreground bounds.
Channel medians select dominant non-white base, stripes/calico dark secondary,
and white (lifted to L≥88); warm bases gain 15% saturation and stay at least
0.45 lightness. This preserves orange coats and near-black tuxedo bases.
Animal eye joints with confidence >0.3 provide discs of radius 0.16× inter-eye
distance (minimum 2px). Iris sampling rejects saturation≤0.18 and value outside
0.22…0.97, uses channel medians, then boosts saturation 15% and value to ≥0.55.
Without usable eyes, orange/brown coats default to green, neutral coats amber,
colorpoints blue; an explicit eye override wins.
Confidence is a heuristic cluster-quality score, not a species-model probability.

`HousePetPhoto.load(from:eye:recognizeSpecies:)` reads a local file through
ImageIO, applies EXIF orientation, downsizes to at most 512px, and runs local
Vision animal recognition (cat/dog/unknown), instance segmentation and animal
body pose. `recognizeSpecies:false` suppresses the species label, not foreground
localization. Masks support OneComponent8, OneComponent32Float (0…1), and
OneComponent16Half, honoring row stride. The instance with greatest overlap
(intersection-over-union) with the recognized animal box wins, otherwise the
largest instance. Erosion removes about 2.5% of the short side at edges. Coverage
outside 3%…92% (or too little remaining after erosion) falls back to an ellipse
inside the animal box, or a centered ellipse without a box. The reusable mask
is one byte per pixel, >127 selects foreground. Pure analysis without a mask
uses all nontransparent pixels. `loadAnalysis` also returns the exact image/mask
in memory for review thumbnails, avoiding a second Vision run.
`Result.pet()` maps a reported dog to `dog-short`, cat to `cat-short`, and unknown
to `cat-short`. Editor photo confirmation, CLI add and photo snapshot panels use
this same mapping. The confirmation species picker or CLI `--species` can override
detection. `set --photo` changes only palette/pattern on an existing pet unless
`--species` is explicit; it never silently changes an existing pet's species.

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
rim). `HouseDoorwayPlanner` supplies the same preferred 0.3-unit openings used by the composer (widest clear
span ≥ 0.2 next, then a forced shared-midpoint opening nudged around shared-wall fixtures when possible):
aligned cell centers get `jump=false`, with `stairs=true` for a 48 px difference.
The lower room's nodes within the selected 0.3 / 0.25 / 0.125-unit stair approach interpolate their elevation
up to the higher floor, so ordinary walking interpolates continuously onto and across
the steps. Other crossings remain cat jumps; 96 px differences are blocked.
Furniture clearance is a preference, not a veto: every eligible pair has a doorway and `coverage.uncovered` is empty.
For each doorway-aligned boundary cell, a deterministic breadth-first search adds the shortest connector to an
existing walkable cell in that room. These runtime-only passages may cross blocked furniture cells; original
`blocks.json`, authored pet walk grids and art stay unchanged. Other blocked cells remain blocked.
Every placed snapshot doorway is tested for a walking crossing and access to existing floor on both sides.
Exact widths, stairs and fallback pairs are listed in
[HOUSE.md, Issue #58 acceptance status](HOUSE.md#issue-58-acceptance-status-2026-10-27).
The shared pet snapshot layout also has a regression test for a bedroom-to-study route containing only non-jump
edges. Its rooms are all level 0, so stairs are expected only in the auto-level fixture/classic layouts.
The classic hand-drawn `house-cutaway.json` and PNGs from `scripts/gen-house-cutaway-art.py` remain unchanged
and need new source art later; pets continue to force the composer for classic geometry.
A* adds **six walk-cell lengths** to every jump's geometric distance, preferring nearby
doorways without forbidding a substantially shorter cat hop. The Euclidean heuristic
remains admissible. A* caches paths;
`path(from:to:room:allowedRooms:)` optionally confines the whole route to a room
or a set of existing rooms. Decor with
`petSpot=true` supplies preferred sleep spots by its resolved slot, projected to
the nearest walk node. An optional decor `species` array restricts eligibility:
`dog_bed` has `["dog"]`, and `cat_bed`/`cat_tree` have `["cat"]`. Missing filters
remain shared. Matching species beds take precedence over shared decor spots;
the other species cannot use them in day plans or night reactions. Without a
matching bed, pets retain generic sleep/perch spots and the room fallback.
Bed/sofa perches rank next, then sleep spots and a room
fallback. Catalog light `pool` centers provide lookup/sit reaction destinations.
Catalog lights whose `role` or `kind` is `ac` instead supply `ac` lounge spots
at the `vent` midpoint (no light `pool` is required). Missing vents use the
floor `alt` anchor, then a point below the module tip. Coordinates are projected
relative to the art tip into floor UV and snapped to the nearest walk node;
generated AC spots have priority 2. AC/entry spots are reaction-only and excluded
from baseline roaming so existing schedule fingerprints remain unchanged.
Entry title/key matching shares
`HouseModule.isEntryFoyer` (简/繁/English entry, foyer, hall, corridor names).
`HousePetWorld.roomTitles` allows opaque room IDs to use their display titles.
An entry room gets a central walk-node `entry` spot (priority 2); no reliable
door-side geometry exists in the current catalog. Authored `ac`/`entry` spots
override generated spots of that kind in their room, without editing every style.

Free floor decor uses this same walk grid (`HouseFreeDecor`, see `HOUSE.md`). Resolved
`free:<id>` placements carry their footprint cell. `HousePetWorld` omits those cells before
building edges, so paths detour around S/M one-cell and L 2×2 obstacles. Its initializer
remains source-compatible: pass resolved placements through the existing `decor` argument
and the item catalog through `items`. Free `petSpot` items create preferred sleep spots
on the nearest remaining floor node, never on their blocked footprint. Validation protects
fixed sleep/perch approach nodes and keeps the remaining room floor connected. Invalid or
disabled free decor is not resolved and therefore does not leave invisible obstacles.
No extra pet occupancy is imposed on fixed decor or cross-room doorway cells by v1.

Keep one `HousePetBehavior(rig:rigs:)` instance (the single-rig initializer remains
compatible). `pose(_:world:context:at:)` is a pure
function of these inputs despite internal plan/path memoization. Stable FNV/LCG
seeding uses the local calendar day and pet ID, never Swift randomized hashes.
The cached day plan alternates 8–60s rest activities and A* movement at 36px/s.
Doorway and stair travel reuse `walk` at 36px/s with zero `jumpLift`, not a new animation.
Remaining cross-module/perch jumps last .5s; `jumpLift` is a positive parabolic displacement
to subtract from screen y. +u faces SE, -u NW, +v SW, -v NE.

Supply `HousePetContext` with existing room keys, active pet IDs, per-room lights,
TV room keys, night state and `changedAt`/`changedRoom`, plus `acRooms` and
`vacuumRooms` (default empty), `entryAt` and `entryRoom` (default nil).
Populate `petSpecies` for mixed-species single-pet calls; `poses` fills it
from the supplied pets automatically. Matching beds reserve by same-species rank.
Keep the same timestamp until the next context change. All new fields participate
in the reaction cache key. First-match priority is **vacuum → entry → nightSleep
→ TV → AC → light**. Vacuum/TV/AC persist while active; ordinary reactions wait
until `date >= changedAt` (or local midnight if absent). Entry uses its own
timestamp, not a later AC/light change, and is eligible only for the half-open
180-second interval `[entryAt, entryAt + 180s)`. Repeated reads do not restart it;
after expiry, the next applicable reaction or baseline takes over. A vacuum can
preempt entry during this window; entry may resume only inside the original window.
Reactions begin from the baseline plan at their event timestamp, not from the
previous reaction. Entry and vacuum travel at 72px/s using walk frames (jumps
remain .5s); arrival at entry/AC sits, arrival at a safe sleep/perch sleeps.
Vacuum prefers reachable sleep/perch spots outside all `vacuumRooms`; when none
are reachable it uses a local sleep/perch. `homeRoom` and allowed-room routing
still apply and are never overridden to escape. Dark night with multiple pets
assigns sorted IDs to reachable sleep/perch
spots ordered by dark room, priority and ID, five cells apart (three-cell fallback)
when enough exist, otherwise keeping the first-reachable-target spread; single pets
still seek the first reachable sleep spot; TV seeks its TV spot; a light change produces
2s lookup then a light-pool sit. `homeRoom` confines routes and rest locations.
Sorted pet IDs partition rest spots five cells apart. TV/light and fallback sleep
reaction destinations use the same spacing, falling back to three, two, then one cell
only if there are too few spots for the roster. Pass the **same roster** to every
pet. `restOnly=true` chooses the current/next rest spot and restricts actions to
idle/sit/sleep, without changing the underlying full-scene day plan. `visible`
also reflects pet/global enablement and missing-room safety.

The overlay derives AC rooms from `.ac && on`, vacuum rooms from vacuum-like
devices with `on || busy`, and refreshes `changedAt`/`changedRoom` when these
sets change. `HouseDevice.model` is copied from `Device.model` (default empty).
`HouseCatalog.isVacuum` checks `deviceClass`'s vacuum fixture, then category raw
value/model/name keywords (`vacuum`, `roborock`, `sweeper`, `.robot.`, 扫地/掃地,
扫拖/掃拖). Thus `.other` vacuums remain visible to the resolver on main, with no
dependency on #54; a future `vacuum` category also matches by raw value. Cached
status goes through `HouseDeviceState.busy`, including cleaning/sweeping/mopping
options, even if the device has no power property. Unknown status falls back to
power. Offline devices do not contribute live power/busy/contact readings.

Entry is a **contact-sensor proxy, not a doorbell detector**. `houseRoom` reads
cached `contact-state` through the existing Notifier snapshot adapter; the overlay
records an event only on a known closed→open transition in an entry-named room.
First observation, unchanged open state, missing data and offline readings do not
trigger an event. No network calls or new polling are added. Refresh cadence still
limits detection; transitions between reads can be missed. As documented by
Notifier, actual doorbell presses cannot yet be detected reliably.

For external visual QA, `--house-pets-snapshot <dir>` additionally writes
`pets-react-ac-{style}.png`, `pets-react-entry-{style}.png`, and
`pets-react-vacuum-{style}.png` for cozy-wood, japanese and modern. These use a
synthetic three-room layout and planner context injected 120 seconds before the
snapshot date, producing an AC lounge, entry arrival and vacuum refuge on the
bed (render time is the selected date plus 120 seconds). Use the existing `--date`
option for a fixed date. They do not require real
devices, device writes or fake doorbell polling. Render these panels externally
when GUI execution is permitted; compilation alone does not verify their visuals.
`poses(_:world:context:at:overrides:)` resolves visible rest-only crowding in sorted-ID
order using the nearest same-room walkable node at three cells' separation, with
two/one-cell fallbacks; explicit overrides stay fixed and reserve their positions.
Animated poses and the single-pet API are unchanged.

## CLI and MCP

```
mijiabar house pets list --json
mijiabar house pets analyze /local/cat.jpg --json
mijiabar house pets add --name Mochi --photo /local/cat.jpg
mijiabar house pets add --species dog --name Shiba --pattern bicolor
mijiabar house pets add --photo /local/dog.jpg
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
`--species cat|dog` selects the corresponding short rig; optional `--rig` must
match that species. Invalid pairs are rejected by `setPet`. `HousePetRig.supported`
owns per-template pattern validation; schema/list pattern enums are their union.

`analyze <photo> [--json]` is read-only and returns pattern, palette, species,
confidence, `usedVisionMask` and `usedEyePose`. Without `--json` it prints named
fields; JSON wraps these fields in `analysis` alongside `ok:true`.
`usedVisionMask` means the selected, eroded Vision mask actually reached the
color analyzer; `usedEyePose` means pose iris samples supplied the eye color.
It requires only agent read access, never resolves a home or reads/writes
`house.json`, and rejects `--home` and appearance mutation flags.

MCP `get_house_pets` returns pets, preferences, patterns/actions and `limit:3`.
`set_house_pets` accepts `op:add|update|remove|enable|disable`, `pet` (ID/name for
update/remove), optional home/name/species/rig/pattern/palette/room/enabled, and `photoPath`
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
set `restOnly`. The app retains its world between ticks, rebuilding on scene,
layout/style/decor changes. Homes with configured pets use the composed module scene
(including the default four-room layout), so walk grids, perches, decoration
spots, clipping and lighting all use identical module coordinates.

## App editor

Open **Enlarge → Edit → Pets**, next to **Style & decor**. **Show pets** is
independent of each pet's enabled toggle. Each card offers a name, six patterned
previews, base/second/white/eye color wells, and **Roam freely** or a room restriction.
Static pattern tiles crop to the opaque bounds of the shown sit SE frame at elapsed zero;
animated card previews crop to the shared union opaque bounds of the sit/idle SE frames.
Both add a one-pixel margin and use integer device-pixel nearest-neighbour scaling (fractional fit only when necessary).
**Add pet → Choose manually** starts an orange tabby & white cat; the species
picker switches it to a dog. Every preview and pattern tile resolves the selected
pet's rig, including the photo confirmation sheet. The three-pet
limit counts disabled pets across both species; remove a pet to free a slot. Remove and all other edits
use the existing window's ⌘Z/redo stack, with fresh timestamps and deletion
tombstones. An independent edit to the same pet invalidates stale undo; restoring
a pet never creates a fourth pet after a concurrent addition.

**Generate from photo…** opens a local image picker. Analysis runs off the main
thread using `HousePetPhoto.load` (Vision foreground mask where available).
The confirmation sheet holds only an in-memory thumbnail, shows an editable
pixel-pet preview, and lets you add or cancel. Dismissing the sheet/editor releases
the thumbnail; only the chosen palette, pattern and pet fields enter `house.json`.
No photo path, thumbnail or Vision mask is persisted or uploaded.

The shared `HousePetPainter` draws anchor-relative, mirrored, nearest-neighbor
frames sorted by foot y, clipped to each composed module's `petVisible` polygons
(falling back to `visible` for older scenes). Doorway regions are shared by both
rooms so crossing pets stay visible, independently of the light-occlusion mask.
Before that clipped pass, the shared window/menu painter draws an unclipped
x-ray silhouette at 30% opacity in the pet's base color darkened to 65%.
Only opaque sprite pixels enter this alpha mask: ground shadows are excluded.
The normal opaque sprite covers the silhouette where visible; hidden parts
remain faintly readable through the low cut-away walls and foreground modules.
Both passes subtract active **same-room furniture** silhouettes: solid furniture
never receives the 30% x-ray. Each hole is intersected separately with the current
clip, so overlapping furniture cannot toggle pixels back on. Pet foot-y sorting
is unchanged. Classic cutaway with pets still uses composed modules.

### Furniture occluders

Each `sets[artSet][module]` may contain `occluders`; absent or empty means the
previous behavior. Old clients ignore this additional field. An entry is:

```json
{"id":"sofa","kind":"sofa","footprint":[0,0,0.375,1],"z":16,"perches":["sofa"]}
```

`footprint` is `[uMin,vMin,uMax,vMax]` in floor grid units (not walk cells),
`z` is positive height in pixels. Optional `silhouette` is an array of `[x,y]`
vertices **relative to the module tip**, not PNG top-left coordinates. Without
it the mask is the six-point outline of a floor quad extruded upward by `z`,
including its front faces. World construction adds the same art tip, compose
offset/origin and level elevation used by walk nodes; polygons are cached in
absolute scene coordinates by room instance, not just module type.

Depth is tested along the camera ray through the foot: invert the floor
projection, keep `u-v` fixed, and intersect that ray with the rectangle. Its
near endpoint is `uFront=min(uMax,vMax+u-v)`, `vFront=uFront-(u-v)`.
No intersection means inactive; otherwise the foot must be strictly behind
`tip.y+66*(uFront+vFront)` and no nearer than that endpoint in floor coordinates
(`u<=uFront`, `v<=vFront`). This includes feet inside the footprint and feet
behind it, but excludes lateral and front feet. Equal front depth is visible.
The test uses the logical foot, not animated `jumpLift`. A stationary pose carries
its resolved `spotID`; at a named `perches` spot with matching `z` and projected
position (within 0.01 px), it bypasses that furniture only. A floor foot at the
same projected pixel is not exempt. Moving/crowd-relocated poses clear the ID;
fixed perch overrides must supply it explicitly.

`python3 scripts/house_pets/occluders.py` regenerates masks without imaging
dependencies; `mkspots.py` also calls it. It starts with `blocks.json`, dividing
cell bounds by `cellsPerGrid`, and authors living sofa (16 px), coffee table
(16 px), bedroom bed (22 px), and bathroom vanity (26 px). Cozy uses explicit
outlines tuned against the existing module PNGs (including the table legs),
rather than masking the whole walk-clearance rectangle. There is no separate
asset mirror of pet-spots.json. Style selection follows `artSets`: light-wood
and walnut inherit cozy directly; Japanese/modern have separate sets whose
generated furniture currently inherits cozy blocks/heights unless overridden
in the generator/blocks. Those two packs need hand-tuned silhouettes and visual
review later; their defaults are prism approximations, not traced PNG masks.
Day-lit cats use `dayLit`. Night-unlit cats use `night`; night-lit cats multiply
the day color by `night.mul` and a per-channel lit/unlit ratio (9×5 foot patch,
clamped to 1…2.6), falling back to `nightLit` if sampling is unavailable.
Ground shadows receive only the night multiplier, never lit-room boosts/addition.

Only the pet layer ticks (8 fps in the window, at most 3 fps in the menu embed).
The embed is rest-only; the menu-bar status icon does not animate. Reduce Motion
and Low Power Mode show quantized static poses refreshed approximately every ten
seconds. Window occlusion pauses pet ticks. Light/TV behavior comes from the
existing room/device state, without extra polling or device writes.

## Synthetic snapshots (manual only)

The existing `--house-pets-snapshot` exporter also writes
`pets-furniture-{style}-{sofa|coffee-table}-{behind|front}.png`. These use a
fixed sitting pose at the footprint center or beyond its near edge, independent
of day plans, and render one cat through the shared painter. Review the behind
and front pairs externally; automated bitmap tests do not validate art alignment.

```bash
.build/debug/MijiaBarApp --house-pets-snapshot /tmp/house-pets --date 2026-10-18
.build/debug/MijiaBarApp --house-pets-snapshot /tmp/house-pets --photos /path/a.jpg,/path/b.jpg
```

The exporter uses an in-memory mock model and the decor exporter's six-room
layout/default decorations, never the real house file or real devices. `--date`
accepts an ISO date or timestamp (default 2026-07-01). It writes:

- `pets-<style>-<day|night>-<unlit|lit>.png` and `-2x.png`, for cozy-wood,
  japanese and modern, with 橘子 sitting on the living-room rug facing SE toward
  the camera, 煤球 walking (frame 2), and 花花 grooming by day/sleeping at night
  on the same elevated bedroom bed sleep spot (including its z).
- `pets-actions-<style>.png`: nine room panels covering idle, walk SE/NE, sit,
  groom, lookup, sleep, stretch and jump.
- `pets-dog-patterns-<style>.png`: six dog pattern panels.
- `pets-dog-actions-<style>.png`: all eight dog actions in both SE and NE (16 panels).
- `pets-world-<style>.png`: walk cells (green), spots (orange), A* path (blue).
- `pets-menubar-day.png`, `pets-menubar-night.png`: the real `HouseListEmbed`
  rendering path, with a fixed date and rest-only behavior.
- `pets-editor-light.png`, `pets-editor-dark.png`: the Pets editor with all three
  demo cards and the full local-analysis privacy footer (1440px review canvas).
- `photo-<n>.png`: source photo at 320 px tall, exact foreground-mask thumbnail
  underneath, arrow, detected palette and bilingual Chinese/English pattern,
  and sit/walk/sleep pets of the detected species enlarged to 9× cell size (3× the previous previews)
  with nearest-neighbor sampling, via the real
  photo pipeline. Only this requested before/after PNG contains photo content;
  never commit it. No photo intermediates or sidecars are written.

Scene exports call the same CoreGraphics painter as the live layer; UI exports
use the existing `Snapshot.render` hosting/cacheDisplay path. Do not execute any
snapshot flags in a sandbox that cannot launch GUI apps; build/tests alone do
not establish visual acceptance. The maintainer runs and reviews these exports.

`package.sh` copies the complete SwiftPM resource bundle, including the processed
pet JSON/PNGs. `verify-app-bundle.sh` checks both rigs, spots and all twelve encoded
sheets. `HousePetPainter.rigs` loads the supported templates through `AppResources`;
`rig(for:)` selects by pet, while `rig` remains a cat-only compatibility accessor.
App loading uses both nested and processed-flat
resource lookups; no implicit package bundle accessor is used.

Art regeneration belongs to `scripts/house_pets/`.
Do not hand-edit encoded sheets or spot assets. After regenerating, run the
golden, grid, sheet and resource tests. Run `swift build` and `scripts/test.sh`;
unit tests must not launch the app or any GUI.
