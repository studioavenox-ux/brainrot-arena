# Phase 4 — the six characters, implemented

Character Production phase: the concept board (`docs/previews/cast.jpg`) is **reference
only**. Every character here is a real, separate, low-poly 3D Roblox Model built from
engine primitives. Nothing in the game loads an image.

## 1. The cast

| # | Model | Species | Rarity | Reward | Parts | Height | Silhouette cue |
|---|---|---|---:|---:|---:|---:|---|
| 1 | **BRAINY** | brain | Common | +1 | 13 | 1.38 | two hemispheres with a seam, stem, one eyebrow |
| 2 | **BLORBO** | frog | Common | +1 | 14 | 1.36 | wide flat head, eyes on top, long folded legs |
| 3 | **GLORP** | fish | Rare | +5 | 12 | 1.23 | egg body, side fins, tail fin, dorsal fin |
| 4 | **HJONK** | goose | Rare | +5 | 13 | 1.49 | long neck, flat bill, wing plates, tail |
| 5 | **CRUSTY** | toast | Legendary | +10 | 12 | 1.37 | slice plate with crust rim, corner ears |
| 6 | **WHIFFERS** | sock | Legendary | +10 | 10 | 1.42 | L-shape, cuff band, stripes, heel ball |

Colours follow the existing rarity palette: pink `(255, 94, 190)` for Common, gold
`(255, 213, 67)` for Rare, cyan `(83, 238, 255)` for Legendary — the same values the
server already pays. Faces are dark ink eyes + brows + a mouth on a +Z-facing surface,
readable at the normal third-person camera distance.

`tools/creatures.py` is the single source of truth. It validates the cast before any
build: 9–14 parts each, no two characters with the same silhouette signature, faces
inside the body surface, every role a known role, every material a real
`Enum.Material`, and a per-cell worst case of 16 parts.

## 2. Six separate, usable models (not one recoloured template)

Each character is an independent part table with its own proportions, joints and
motion — the validator fails the build if two silhouettes collide.

Baked into **both** place files under `Workspace → BrainrotCharacters`:

- six `Model`s named `BRAINY`, `BLORBO`, `GLORP`, `HJONK`, `CRUSTY`, `WHIFFERS`
- each with a `PrimaryPart` on its own body so Studio's pivot and selection behave
- every part anchored, `CanCollide/CanTouch/CanQuery/CastShadow` off, massless
- a `LabelAnchor` part carrying a `BillboardGui` (`Name` + `Rarity` labels), so the
  floating name and rarity card exist in the saved place, not only in code
- a `Plinth_<species>` limestone block under each, standing on the lobby terrace step
  at `y 21.6`, in the row `x −7.75 … 7.75`, `z 199.0`, all facing the spawn pad

The same data is instantiated at runtime (`src/client/Creatures.luau:Build`) for the
48 arena cells and for the six collection viewports, so a plate, a card and a live
pickup can never show different geometry.

## 3. Animation and effects

- **Idle** — per-character `Bob`, `Sway`, `Rate` and `Spin`, driven from one clock, with
  jointed head sway, jaw chatter, arm swing and tail wag. Collapses to a still pose
  under the reduced-motion preference.
- **Collect** — spin + pop + rise (`Creatures.Collect`), played when the server's
  receipt arrives, followed by the pickup burst in `Effects:collectAnimation`.
- **Pickup FX** — receipt-driven spark burst tinted by rarity, plus the floating
  `+N` label; the halo ring stays the shared "this is a cell" cue.
- **Collection cards** — each card runs the character's own idle on a slow turntable.

## 4. Gameplay integration

The reward model is unchanged and stays server-authoritative:

1. `PickupLedger.rollKind` picks the denomination (78 / 18 / 4 weighting) on the server.
2. It then rolls the species from that family with `SpeciesOf(slotId, value)`
   (brain/frog, fish/goose, toast/sock) and publishes `Species` on the pickup part.
3. The client can only *animate* a receipt. `RoundMachine:award(id, value, roundId,
   species)` re-validates the round, participation and that `value` is exactly
   1, 5 or 10, then increments score and records the species.
4. Duplicate collection is impossible: a slot is consumed once per round inside the
   ledger's atomic pickup, and the same round/part cannot award twice.
5. Appearance never feeds scoring — each family has two members worth the same value.

`Row.collection` (species → count) and `Row.collected` (distinct, 0–6) ride the existing
snapshot to the HUD.

## 5. Collection interface

`src/client/Collection.luau` — a full-screen specimen log opened by the gear button,
the `SPECIMENS n / 6` chip under the coin counter, or the **C** key:

- six cards, each a live `ViewportFrame` of the real model on a plinth with a
  rarity-coloured rim
- each card shows the name, rarity + reward, catch count, and a short blurb
- uncaught specimens render as dimmed silhouettes reading `NOT SEEN YET` — the log
  never pretends a character was caught
- header: `SPECIMEN LOG`, `n / 6 CHARACTERS LOGGED • n CELLS CAUGHT THIS SESSION • n COINS`
- responsive grid (3 across on desktop, 2 on phones), `C` closes it, `Escape` closes it
  before any other panel

## 6. Verification

`python3 tools/check.py` → **221 passed, 0 failed** across eight gates:

| Gate | Tests | What it proves for this phase |
|---|---:|---|
| Core Luau (`tests/core.spec.luau`) | 90 | species roll per family, distinct counts, award rejects bad value/round, duplicate pickup, collection snapshot |
| Adapters (`tests/adapters.spec.luau`) | 60 | model build, label anchors, idle motion, collect animation, collection screen structure and toggles |
| Place XML (`tools/verify_place.py`) | 36 | six named Models, parts identical to the generator, feet on plinths, labels matching the game copy, collision limited to plinths, exhibit inside the terrace |
| Art gate (`tools/artcheck.py`) | 31 | palette, hierarchy, legibility, lighting, 16-part cell budget, silhouette separation |
| Luau compile | 24 files | every script compiles |
| Strict analysis | 4 modules | authority modules + Config |
| Deterministic rebuild | — | byte-identical exports |
| Whitespace | — | clean diff |

**Not verified:** Roblox Studio was not available in this environment. Nothing here is
claimed as engine-tested. Open `places/BrainrotArena-QuickTest.rbxlx`, start 2 clients,
walk the lobby exhibit, press **C**, and catch one of each species.

See `docs/previews/cast.jpg` (cast sheet), `docs/previews/collection.jpg` (lobby
exhibit), and `docs/previews/ui-collection*.jpg` (the specimen log).
