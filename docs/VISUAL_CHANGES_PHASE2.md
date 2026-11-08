# BRAINROT ARENA — Phase 2 Visual Change Report
### Professional visual polish: architecture, cast, HUD, effects

**Scope:** appearance only. No gameplay mechanic, scoring rule, round timer, pickup
position, rarity weight, coin/cosmetic rule or multiplayer message was changed.
`src/shared/Config.luau`, `src/server/core/{RoundMachine,PickupLedger,MovementGuard}.luau`
and every remote are byte-identical to the merged Phase 1 build.

**Verified:** 164 automated checks pass — 72 core Luau, 32 adapter, 30 place, and a
30-test art-direction gate that includes the frozen walkable-geometry regression.
Roblox Studio is not installed here, so **engine rendering is still unverified**
(see [What is verified](#10-what-is-verified-and-what-is-not)).

**This phase continues** `docs/VISUAL_CHANGES.md` (Phase 1: palette, lighting,
materials, hierarchy). Phase 2 is about *architecture, characters, interface and
motion* — the things that make a stylised scene read as a produced game rather than
a recoloured prototype.

| | Phase 1 | **Phase 2** |
|---|---|---|
| Static parts | 588 | **824** |
| Exported instances | 601 | **831** |
| Collectible designs | 1 (six-lobed brain) | **6 original critters** |
| In-world signs | 5 | **7** |
| Point lights | 7 | 7 (unchanged — see §6) |
| Materials | 14 | 14 |
| Automated checks | 158 | **164** |

---

## 1. What was wrong after Phase 1

Phase 1 fixed the colour problem. Screenshots still showed four structural gaps:

1. **The island had no architecture.** Every structure was a flat panel, a rail or a
   palm. The lobby was a lawn with two boards on it; the arena was a sand disc with a
   beacon. There was no floor plane / support / roof vocabulary, so nothing read as a
   *built* place.
2. **One collectible, six slots.** 48 identical brains, distinguished only by hue and
   a floating spike. Fun for ten seconds, and it put all the personality of the game
   into a single shape.
3. **The HUD was one flat rectangle stack.** No hierarchy, no dividers, no gradient,
   no creature identity — the top-left wordmark and the rarity key competed with the
   round clock at the same visual weight.
4. **The world ended at the island edge.** Islands hung in a void; the eye had nowhere
   to travel, which made the scene read as a test map.

---

## 2. Architecture: from "props on a disc" to a built resort

A new module, `tools/terrain_aug.py`, holds the Phase 2 structures. It uses the *same*
primitive vocabulary as `tools/world.py` (block, ball, cylinder, wedge) through four
new helpers — `beam` (a block spanning two points), `cone` (a tiered parasol roof),
`gable_roof` (two pitched halves) and `rotate2d` (local placement) — so every new
building is still plain, editable Roblox geometry. **No meshes, models, unions, decals
or asset ids were introduced** (asserted by `artcheck` test 30).

### 2.1 The arena promenade

Four buildings on the diagonal promenade at radius 44, each with a floor plane,
vertical supports, a roof and one warm lantern:

| Structure | Position | What makes it read | Part cost |
|---|---|---|---|
| **Tea pavilion** | `(36.6, 24.4)` | 4 posts on the diagonals, brace beams, 3-tier parasol roof, finial, tea table and two stools | 28 |
| **Lookout tower** | `(-36.6, -24.4)` | braced legs, plank deck, railing, 6-sided roof, ladder rails + rungs, signal lamp | 27 |
| **Beach bar** | `(24.4, -36.6)` | plaster back wall, counter + skirt, pitched awning with a ridge beam, crates, three stools | 17 |
| **Shore shrine** | `(-24.4, 36.6)` | three stone terraces, 4-block carved totem with relief bands, votive orb, low walls, two banners | 16 |

The **beacon terrace** was rebuilt as a monument: four diagonal pylons with lantern
caps, four link walls, four carved plinth fins and a pair of braziers ring the existing
stairs. The beacon brain itself is 25% larger and sits 0.8 studs higher, so the
landmark is legible from the satellites.

### 2.2 Satellites stop being copies of each other

Each of the four platforms now owns one distinct landmark, placed clear of its three
pickup slots and its palm:

- **North-west — timber dock.** Three deck sections on pilings reaching off the island
  edge, crates, bollards and a mooring lamp. This is the only structure that leaves the
  island footprint, which is exactly why it reads as *going somewhere*.
- **West — small lookout tower.** Four legs, deck, rails, parasol roof and three stairs.
- **North — garden shrine.** Stepped plinth, three-block totem, votive orb and three
  shrubs in stone planters.
- **South — beach camp.** Canvas tent with wings, fire pit ringed with stones and an
  ember, two log seats.

### 2.3 The lobby is now an arrival sequence

The lobby is where every player spawns, so it received the most detail:

1. **Amphitheatre terrace** behind the spawn: two stone steps, a five-part hedge line
   and two lantern pillars.
2. **Halo kiosk** off the plaza: floor, four posts, back wall, counter, pitched roof,
   lamp, crates and a live price board (`Lobby_KioskBoard`).
3. **Pergola promenades** over both bench rows: five posts, two beams, six slats and
   three vine clumps per side.
4. **Bunting** strung across the gate opening, with four clay pennants and a line.
5. **Plaza planting**: stone planters with flowering shrubs on both sides of the path.
6. **Twin lamp posts** flanking the welcome path, so the spawn reads as an entrance.
7. **Wayfinding plaque** beside the gate — `ARENA / THIS WAY → / 3 MINUTES • AUTO JOIN`.

### 2.4 Nature, ground plane and skyline

- **The sea.** Two huge discs at y≈5–6 plus a shallow tint ring turn four floating
  islands into an archipelago: `Sea_Shelf` / `Sea_Surface` / `Sea_Shallow`. Three new
  low-chroma palette entries (`sea_deep 52,92,108`, `sea_tint 74,122,133`,
  `sea_shallow 104,152,152`) keep them *cooler* than stone teal while staying inside the
  environment chroma ceiling. The horizon is what finally gives the scene depth.
- **Island undersides.** Each island's cliff is now a ring of 10 small rock facets with
  a per-facet wobble instead of 6 giant planes. Same silhouette logic, no more 40-stud
  flat faces catching one huge highlight.
- **Float islets.** The four decorative sky shards are rebuilt from balls (rock, lower
  rock, keel) with a small prism signal — rounded, deliberate islands rather than
  cropped wedges.
- **Ground cover.** Driftwood and fern clumps alternate round the arena beach,
  flower patches with clay blooms sit on the outer sand, shrubs fringe the lobby lawn,
  and every satellite gets two planted beds.

---

## 3. The cast: six original collectibles

The single most visible change. `tools/creatures.py` is the single source of truth:
`tools/build_place.py` generates `src/client/CreatureData.luau` from it,
`src/client/Creatures.luau` instantiates the primitives, and `tools/preview.py` renders
the same tables — the export, the runtime and the review plate cannot drift apart.

| Rarity | Family | Critters | Mark |
|---|---|---|---|
| pink **+1** | small critters | **Brain Cell** (6 lobes, dark seam, stem) · **Brick Frog** (flat body, two eye domes, cream toes) | none |
| gold **+5** | sea / land birds | **Wobble Fish** (round body, fan tail, dorsal fin, cream side fins) · **Silly Goose** (long neck, forward beak, feet) | floating ring |
| prism **+10** | weird relics | **Toaster Cat** (box body, cat ears, toast poking out of the slot) · **Sentient Sock** (foot, leg, heel, cream cuff + stripe) | crossed arms |

Design rules, all machine-checked:

- **Rarity drives family, family drives silhouette.** +1 is small and round, +5 is
  animal-shaped with a long axis, +10 is a boxy object. The three tiers cannot be
  confused at distance even in greyscale.
- **Variants are shapes, not recolours.** The two variants inside a family differ in
  part count *and* in height/width extents (`artcheck` test 26).
- **Which variant appears is decided on the client only**, deterministically from the
  slot id (`slot_id % 2`). The server still knows nothing but a rarity value, so
  appearance cannot feed back into scoring, claiming or respawn timing.
- **Faces use fixed neutral inks** (eye `32,37,43`, cream `238,230,212`), never the
  rarity colour, so every critter has an actual face instead of a coloured frown.
- **Budget.** 5–9 primitives each; worst case 12 parts per cell including the pivot,
  the shared hover ring and the rarity marks — inside the existing 14-part allowance
  per slot (`creatures.PART_BUDGET`, asserted in `artcheck` tests 25 and 29).

### 3.1 Runtime behaviour (`src/client/Creatures.luau`, `Effects.luau`)

- One model per slot, built lazily and **rebuilt only when the rarity changes**, never
  per frame. `syncCreature` recolours in place when only the value's colour moved.
- 30 Hz update continues: hover (`sin` bob), slow idle spin, and a small tilt. Rare
  cells breathe — the gold ring and the prism arms pulse, so value is visible before
  you read the glyph.
- New: the hover ring is a single flat disc — **axis-corrected** so it is a ring, not a
  vertical hoop (Roblox cylinders run along local X).
- New: cells beyond 150 studs are hidden and skip their transform work, so a full round
  in the lobby costs nothing.
- **Reduced motion** still flattens every animation to a static, visible cell.

### 3.2 Preview

`docs/previews/cast.jpg` is a new, deterministic **cast sheet** rendered from the same
tables: six critters, one row, neutral studio stage, halo and rarity marks included. It
is generated with `python3 tools/preview.py --only cast` and is deliberately excluded
from the default plate run (it is a character sheet, not a world view).

---

## 4. HUD and typography

`src/client/Hud.luau` keeps every control, size breakpoint, touch clearance and
keybinding. The polish is structural:

- **Brand lockup**: `BRAINROT` (GothamBlack 30, gold) over a 46×3 pink accent rule,
  `A R E N A` in white, a sentence-case tagline, and a small `SESSION • LIVE` line —
  so the corner reads as a logo block rather than three stacked labels.
- **Panel depth**: every panel now carries a vertical `UIGradient`
  (`38,50,56 → 22,30,34`) over the existing corner and 1px stroke. It degrades
  gracefully: if `ColorSequence` is unavailable (the test mock), the panel stays flat
  instead of failing to build.
- **Dividers**: a 1px hairline under the round clock, at the top of the coin panel and
  under the leaderboard heading. These replace the ambiguous whitespace gaps.
- **Rarity key with names**: `+1 BRAIN / FROG`, `+5 FISH / GOOSE`, `+10 TOAST / SOCK`,
  each with its existing procedural glyph.
- **Creature identity**: the score panel gained a second caption line, and the results
  card now prints `N CELLS • <critter blurb>` chosen deterministically from the round
  id — flavour text only, no gameplay effect.
- **Notices and help copy** now name the cast (`Brain +1 • Fish +5 • Toast +10`) while
  the rarity colours themselves are unchanged and still documented in the rules board.
- **Coin panel** gained a gold coin dot and lost none of its compact layout.

All HUD text stays on Gotham (Black / Bold / Medium); the HUD palette is still the
warm charcoal-teal set from Phase 1, and the art gate still checks contrast for every
in-world sign.

---

## 5. Effects and motion

- Rare-cell halo breathing (above) — value legibility, not decoration.
- Rarity marks are `Neon` and always *outside* the creature silhouette, so the critter
  is never tinted by its reward tier.
- Existing pickup feedback is untouched: score popup, 7-ball spark burst, server chime,
  score pulse, low-gravity colour grade. All of it still respects **reduced motion**.
- The world's own motion cues are static by design (anchored parts): the scene reads as
  still, and all animation lives on the collectibles and the HUD — cheap on mobile and
  impossible to desync from the server.

---

## 6. Performance

| Metric | Phase 1 | Phase 2 | Note |
|---|---|---|---|
| Static parts | 588 | **824** | 236 added buildings, planted ground and sea |
| Layer chroma (ground / nature / props / hero) | 13.9 / 32.0 / 16.0 / 54.4 | **15.7 / 26.5 / 18.2 / 50.0** | hierarchy preserved |
| Runtime ceiling | 1 060 | **1 500** | 824 + 48 cells × 14 worst case |
| Shadow casters | 327 | **410** | 50% of parts, below the 72% ceiling |
| Point lights | 7 | **7** | new lanterns reuse existing light budget; no light was added |
| Materials | 14 | 14 | no new material families |
| Triangle-heavy parts | — | none | no meshes, spheres capped at 7×13, cylinders at 14–30 segments |

Cheap choices made deliberately: roofs are three stacked cylinders (3 parts) instead of
a ring of wedge gables (8 parts, which also produced ugly 20-stud facets at close
range); the sea is two discs rather than terrain water; hangings and bunting are single
parts; every lantern reuses a palette entry that already existed.

---

## 7. Gameplay preservation

- **Nothing that was walkable moved.** `artcheck` test 18 now asserts the Phase 1
  collidable set is a *subset* of the new one — nothing removed, nothing moved, size or
  rotation changed — and that the set actually grew by the new structures. Sign panels
  remain the named exemption.
- **Pickups and spawns are byte-identical**: 48 slots at y = 23.5, 8 arena spawns,
  8 lobby spawns (test 19).
- **Every new collider was placed clear of every pickup slot and spawn pad**, and low
  decorative terraces are intentionally non-colliding so no player can be penned in.
- **Rarity values and weights are untouched** (`78 / 18 / 4`, `1 / 5 / 10`), asserted in
  the art gate from `Config.luau` itself.
- The server, remotes, round machine and movement guard are unmodified; the client only
  reads attributes it already read.

---

## 8. Files

**Added**

- `tools/terrain_aug.py` — Phase 2 architecture, satellites, lobby, nature pass.
- `tools/creatures.py` — the cast specification + budget/validation guards.
- `src/client/Creatures.luau` — runtime builder (tint roles, halo, rebuild policy).
- `src/client/CreatureData.luau` — generated data (do not edit by hand).
- `docs/previews/cast.jpg` — cast sheet.
- This report.

**Changed**

- `tools/world.py` — helper set (`beam`, `cone`, `gable_roof`, `rotate2d`), sea, island
  undersides, float islets, bigger beacon, foliage markers, call-outs to `terrain_aug`.
- `tools/theme.py` — sea palette, plaster/timber/clay accents, `shade()`, warmer grade
  (`ClockTime 16.15`, exposure `+0.09`, softer shadows).
- `tools/build_place.py` — now also generates `CreatureData.luau`, validated.
- `tools/preview.py` — renders the real creatures, the cast sheet, sea and buildings.
- `tools/artcheck.py` — 6 new tests (24–29), additive-collider rule, sea exemption.
- `src/client/Effects.luau` — creature models, pooled marks, distance culling, halo
  breathing.
- `src/client/Iconography.luau` — marks rebuilt around the cast (ring / crossed arms).
- `src/client/Hud.luau` — brand lockup, gradients, dividers, cast naming, results line.
- `tools/{verify_place,check,package_release}.py`, `tests/adapters.spec.luau` — new
  part and sign counts, budgets.

---

## 9. Numbers, as built

```
static parts            824   (95 → 588 → 824 across the three passes)
exported instances      831   (824 + 7 baked sign boards)
collidable parts        162
shadow casters          410   (50%)
materials used          14
pickup slots            48    y = 23.5, unchanged
arena / lobby spawns    8 / 8 unchanged
point lights            7     all shadowless
creatures               6     (2 per rarity, 5–9 parts each)
worst-case cell parts   12    (pivot + creature + ring + marks)
```

---

## 10. What is verified, and what is not

**Verified in this workspace**

- All 164 checks: Luau compile + 72 core simulation tests, 32 mocked-Roblox adapter
  tests, 30 place-structure tests, 30 art-direction tests.
- Deterministic rebuild: the `.rbxlx` exports are regenerated and compared byte for
  byte; `verification.json` records the source and place hashes the ZIP is checked
  against.
- Every creature is inside its part budget, in silhouette order, with deterministic
  variant assignment, using only palette-legal primitive parts.
- The 11 preview plates are rendered from the same tables the game uses.

**Not verified**

- **Roblox Studio rendering.** Lighting, Bloom/Atmosphere interaction, shadow quality,
  material appearance and the real HUD on a device are all engine-side. The plates
  are a numpy rasteriser approximation, not engine screenshots.
- **Frame time on low-end mobile** with 824 static parts. The budget argument above is
  analytic; it has not been profiled in Studio.
- **Face readability at gameplay distance** — the cast sheet is close-up by design; the
  play plate is the honest check, and it is a rasteriser.

Open the place, press Play, and inspect from the lobby spawn before judging the
lighting.
