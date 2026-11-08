# Phase 3 — UI implementation report

The interface was rebuilt from scratch on a design system rather than restyled
piecemeal. Everything on screen is server data; nothing is a hardcoded statistic and
no button is decorative.

Plates (software renders from the same design data, **not** engine screenshots):
`docs/previews/ui-desktop.jpg`, `ui-laptop.jpg`, `ui-phone.jpg`,
`ui-phone-landscape.jpg`, `ui-lobby.jpg`, `ui-results.jpg`, `ui-shop.jpg`,
`ui-inventory.jpg`, `ui-settings.jpg`, `ui-phone-shop.jpg`.

---

## 1. Design system — one source of truth

`tools/ui.py` defines colour, transparency, type scale, spacing, motion, radius,
glyph specs and every copy string. `tools/build_place.py` generates
`src/client/Theme.luau` from it, exactly like the world palette is generated from
`tools/theme.py`. Consequences:

- the HUD cannot drift from the specification, and hand-editing `Theme.luau` fails
  the build (`artcheck test_32`);
- `tools/uidraw.py` renders the plates from the *same* module, so a preview can never
  show a colour the game does not use;
- no uploaded fonts, no asset IDs, no images: every icon is frames and rounded
  corners built in `src/client/Panels.luau` (`glyph`).

### Palette

| Role | Value | Used for |
|------|-------|----------|
| Void / Navy / NavyRaised / NavyEdge | `#0A0E1A` `#101626` `#192136` `#2C3856` | panel stack, darkest → lightest |
| White / Muted / Dim | `#EEF3FF` `#A0AECA` `#707E9A` | primary, secondary, tertiary text |
| **Cyan** `#56E0FF` | structure, round timer, cells, tier 3 | |
| **Violet** `#9E78FF` | brand, navigation, tier 1 | |
| **Amber** `#FFC75C` | currency, winner, tier 2 | |
| Danger / Success | `#FF6C8A` `#76F0B2` | last-15-seconds clock, confirmations |

Every panel carries a four-step vertical gradient (top light → base) and a 1 px
`NavyEdge` hairline at 45 % opacity. Radius 14 in panels, 12 in buttons, 9 in list
rows.

### Legibility measured, not eyeballed

`tools/ui.py:validate()` is run by both the generator and the art gate. It enforces:

- WCAG-ish contrast floors for nine text/background pairs;
- the same floors **composited over sunlit sand** (`#D6C49E`, the brightest thing the
  HUD ever sits on): `White 14.3:1`, `Muted 7.1:1`, `Cyan 10.1:1`, `Amber 10.3:1`,
  `Violet 5.0:1`;
- accent separation by **hue** (cyan↔violet 66°, cyan↔amber 152°, violet↔amber 142°) —
  luminance equality is fine, identical-looking accents are not;
- a strictly increasing type scale and a correctly ordered panel stack.

## 2. What is on screen

### Top HUD (`Panels.topHud`)

- **Brain cells** — left panel, procedural lobe glyph, count from `row.score`, and a
  `Back` easing scale-pulse when the local score increases.
- **Round clock** — centre, `Display` 34 type, counts down from the server's
  `phaseEndsAt` using `Workspace:GetServerTimeNow()` (no local drift), turns `Danger`
  in the last 15 seconds, and labels the phase (`WAITING FOR BRAINS`, `GET READY`,
  `COLLECT`, `ROUND COMPLETE`) plus the round number.
- **Coins** — right, amber disc glyph, count from `row.coins`.
- Brand lockup (wordmark + cyan rule + `ARENA` + tagline) on desktop only.

### Leaderboard (`Panels.leaderboard`)

Right-hand panel, `THIS ROUND / MOST CELLS WINS`, one row per player: rank, name
(with `• you` on your own row), cell count. Ordered server-side and re-sorted on the
client as a safety net, so a stale snapshot can never show a lower score above a
higher one. Rank 1 gets an amber accent bar; your row is raised. Collapses behind a
**RANKS** chip on phone-width screens; **Tab** toggles it.

### Centre notifications

- **Toast** (`Hud:notice`) — pickup receipts and server messages ("Not enough session
  coins"), 3.6 s, accent bar per severity.
- **Event banner** — `LOW GRAVITY • 00:18` with a live countdown, driven by
  `state.eventActive` / `eventEndsAt`, pulsing dot.
- **Lobby panel** — welcome copy, phase word, and `ARENA OPENS IN mm:ss` /
  `NEXT ROUND IN mm:ss` / `WAITING FOR THE FIRST PLAYER`.
- **Results card** — winner, tie ("A MEETING OF MINDS"), or no-score state; cells
  scored; the deterministic cast flavour line; the coin reward **that player** earned
  from `results.rewards[userId]`; and the intermission countdown. It rises and fades
  in with `Kit.enter`.

### Bottom bar and cards

| Button | Opens | Acts on |
|--------|-------|---------|
| **SHOP** | Halo stand | real balance, `Halo` remote verb, server decides ownership and price; the label flips `UNLOCK • 100` → `EQUIP` → `UNEQUIP` |
| **GEAR** | Your loadout | real round score, wins, cells claimed, session coins, halo state |
| **SETTINGS** | Settings | SFX on/off, reduced motion on/off (local only, never a gameplay request) |
| `?` / **H** | How to play | three-step rules card |
| **RANKS** / **Tab** | Leaderboard | show/hide |
| **X** / **Esc** | — | close the current card |

Every button is built by `Kit.button`, which `assert`s that an `onClick` handler was
passed — a button without behaviour cannot be constructed, and `artcheck test_34`
fails the build if anyone bypasses the kit with a raw `Instance.new("TextButton")`.

## 3. Motion

Short, purposeful, all through `TweenService`: buttons scale to 1.03 on hover and 0.96
on press, panels rise 12 px and settle over 0.28 s, the score counter pulses on gain.
Durations live in `Theme.Motion`. **Reduced motion** (Settings) snaps everything to its
end state — no tweens, no camera pulses, no halo breathing — and never changes
gameplay.

## 4. Responsiveness

`Hud:resize()` reacts to `AbsoluteSize` (not once at load) and classifies the viewport
into `compact` (< 780 px wide) and `short` (< 520 px tall):

| Viewport | Layout |
|----------|--------|
| ≥ 780 × 520 (desktop/tablet) | brand lockup + tagline, cell panel under it, centred clock with round label, coins top-right, rarity key and legend under the action bar |
| 844 × 354 (phone landscape) | brand hidden, compact counters, clock 62 px tall, RANKS chip moved up to y = 40 clear of the toast band |
| 390 × 800 (phone portrait) | compact counters 128/112 px, clock narrows to keep the centre line, legend hidden, action bar lifted 118 px above the bottom so it never sits on the thumbstick or jump button |

All measurements come from the mock's layout maths (it honours `UIPadding`,
`UIScale`, `AnchorPoint` and nested scale sizes), asserted for six viewports in
`mobile HUD stays inside safe bounds…`.

## 5. Verification actually performed

All automated, against the mocked Roblox boundary — **no Studio run** (see
limitations).

`python3 tools/check.py` → **198 tests, 0 failed**:

- 52 adapter tests, of which the interface ones are: HUD construction and snapshot
  sync; score updates only after a server pickup (a forged `Score` request changes
  nothing); results card content and reward; help/sound/motion controls; RANKS
  toggle; safe-bounds and overlap at 320×568, 360×740, 390×800, 430×900, 844×354 and
  1280×720; shop/inventory/settings acting on real state (including the empty-wallet
  refusal); a successful purchase flipping the label to `UNEQUIP`; live leaderboard
  ordering and names; phase-driven clock/lobby/results; chaos-event banner appearing
  and clearing; keyboard shortcuts; two clients rendering the same roster.
- 34 art-direction tests, of which 4 are new UI gates (contrast/hue rules, generated
  theme in sync, no hardcoded colours or raw buttons, every button wired).
- Core and export suites unchanged in behaviour (the world is untouched).

## 6. Honest limitations

- **No engine verification.** Roblox Studio is not available in this environment.
  Rendering, real font metrics, `TextWrapped` behaviour at the rendered size, touch
  hit-testing and tween smoothness are all unverified. The plates are software renders
  produced from the design data; they are labelled as such in-frame.
- **Text fit is asserted structurally, not visually.** The mock clips to declared
  widths; Roblox could still wrap a line differently on a device with a different
  font rasteriser. Long display names are the main risk — they truncate with
  `TextTruncate.AtEnd`, but the truncation point is untested on a real device.
- **`ColorSequence`/`NumberSequence` availability.** `Kit.gradient` and `Kit.scrim`
  check for those constructors and degrade to a flat fill / flat wash if absent. Real
  Roblox always has them; the guard exists because the API fixture models the
  boundary conservatively.
- **Preferences are per session.** SFX and reduced motion reset on respawn/rejoin;
  there is deliberately no DataStore (Phase 1/2 constraint).
- Mobile safe-area insets are requested via `ScreenInsets = CoreUISafeInsets`, but the
  notch/home-indicator behaviour of a real device was not tested.
