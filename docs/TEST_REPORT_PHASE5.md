# Phase 5 Test Report

**Status: automated checks pass; Roblox Studio acceptance is PENDING.**

Roblox Studio is not available in this build environment. Nothing in this document
claims a Studio run. The two categories below are kept deliberately separate, as
the spec requires.

* **Automated** — 248 assertions, runnable now with `python3 tools/check.py`.
* **Studio matrix** — the hands-on pass a human must run in Roblox Studio before
  publishing. Every row is marked pending.

---

## 1. Automated checks — 248 passed, 0 failed

```
python3 tools/check.py
```

| Suite | Count | What it executes |
| --- | --- | --- |
| Core rules (Luau, official CLI) | 107 | `RoundMachine`, `PickupLedger`, `MovementGuard`, `ArenaRoute`, `Creatures`, `Config` |
| Adapters (Luau, mocked Roblox) | 70 | the real `Main.server`, `Main.client`, `Hud`, `Panels`, `EventDirector`, `Persistence` against a scripted engine |
| Place structure (Python) | 36 | the exported `.rbxlx`: schema, parts, spawns, baked geometry, budgets, no external assets |
| Art direction (Python) | 35 | palette, contrast, hierarchy, lighting rig, per-cell part budget, event geometry |

Plus, inside the same gate: all 26 Luau files compile, strict analysis of the
authority modules passes, the export rebuilds byte-identically, and `git diff`
is whitespace-clean.

### New Phase 5 assertions (what each one proves)

Stealing — core (all in `tests/core.spec.luau`):

| Assertion | Proves |
| --- | --- |
| a carried cell moves, score included | the transfer is symmetric: victim −v, thief +v |
| the biggest carried cell is taken first | deterministic target selection |
| a thief out of range is refused, nothing moves | distance is enforced server-side |
| the cooldown is server time | a second tag before 8 s is refused, then allowed |
| spawn protection cannot be spam-bypassed | protection is a clock, not a flag |
| a victim who was just robbed is immune | 4 s window after a steal |
| the same pair cannot be farmed inside 12 s | no repeated unfair targeting |
| nothing is taken from an empty pile | no free value from a refusal |
| banked score is never stolen | §9: carried only, never permanent |
| self / idle player / wrong round refused | malformed requests cannot score |

Stages and events — core:

| Assertion | Proves |
| --- | --- |
| the timeline starts at Collect and ends at Final | the production stage table is reachable |
| every boundary banks the carried pile and keeps the score | banking is additive, never destructive |
| carried cells are exposed in the Compete window | there is a real risk window |
| the production schedule warns before every window | `WarningAt < StartsAt < EndsAt < round` |
| five survival kinds exist and all are labelled | no unlabelled event can reach the HUD |
| a warning fires before the event, then the event itself | warning → active → closed lifecycle |
| a finished round never leaves an event open | no stuck gravity/friction |

Stealing and persistence — adapters (`tests/adapters.spec.luau`, real server code
on a mocked engine):

| Assertion | Proves |
| --- | --- |
| a real client tag moves a carried cell and reports both sides | the whole path: remote → resolver → machine → leaderstats → both clients |
| out of range is refused by the server | the client cannot force a steal |
| the request carries no arguments | forged targets/prices are rejected by the whitelist |
| a missing record becomes a valid default profile | first join |
| corrupt fields are repaired, not trusted | hostile/corrupt save data cannot reach gameplay |
| only the six known halos can be equipped | no unknown cosmetic ids |
| a round is paid once, from the server's result | coins/stats are additive and monotonic |
| coins are spend-proof — a halo costs its server price | no client-side pricing |
| a saved profile reloads with the same coins and specimens | durability round-trip |
| an unavailable DataStore degrades to memory | storage outage cannot break a round |

## 2. Studio acceptance matrix — PENDING

To be run in Roblox Studio, in this order. Tick each row only when observed.

| # | Test | How | Expected | Status |
| --- | --- | --- | --- | --- |
| 1 | Two-player multiplayer join | Studio → Test → 2 players | both spawn in the lobby, both teleport to the arena at the bell | ☐ pending |
| 2 | Lobby → arena teleportation | watch a full intermission | every character lands on a distinct arena pad, none stranded | ☐ pending |
| 3 | Collection | walk into a cell | cell disappears, score +1/+5/+10, sound + flash, `SPECS` ticks | ☐ pending |
| 4 | No duplicate awards | two players touch one cell | exactly one award | ☐ pending |
| 5 | Steal happy path | stand within 13 studs, press E / tap STEAL | victim loses one carried cell, thief gains it, both see a message | ☐ pending |
| 6 | Steal cooldown | press STEAL twice quickly | second press shows `RECHARGING`, server refuses | ☐ pending |
| 7 | Spawn protection | tag a player right after they respawn | `PROTECTED`, no transfer | ☐ pending |
| 8 | Banked cells are safe | steal from a player who banked at a stage boundary | `NOTHING TO TAKE`, their score is unchanged | ☐ pending |
| 9 | Round transitions | watch a full 180 s round | Collect → Compete → Chaos → Final → Results, all server-driven, clock header follows | ☐ pending |
| 10 | Event warnings | watch the banner before each event | `INCOMING` counts down, then `ACTIVE` with the remaining time | ☐ pending |
| 11 | Low gravity | play the 60 s window | floaty jumps; gravity snaps back the moment the window closes | ☐ pending |
| 12 | Slippery | play the slippery wildcard | players slide; friction back to normal after | ☐ pending |
| 13 | Moving platforms | stand on a raft during the wildcard | rafts orbit smoothly, players ride them, rafts park afterwards | ☐ pending |
| 14 | Vanishing paths | walk a span during the wildcard | spans are solid, blink in the last 3 s, vanish, fall rescue returns you | ☐ pending |
| 15 | Collectible rush | watch cell respawns in the window | respawn ~1.5 s, back to 5 s after | ☐ pending |
| 16 | Respawning | fall into the void | rescued to the arena, protection applied, score kept, carried cells kept | ☐ pending |
| 17 | UI scaling | 1280×720, 1024×640, 390×800, 844×354 | nothing clipped: brand hidden on phones, clock centred, steal button reachable, RANKS chip not overlapping | ☐ pending |
| 18 | Data persistence | earn coins, buy the halo, leave, rejoin | coins and halo restored; round score starts at 0 | ☐ pending |
| 19 | DataStore outage | run with the API disabled | the server logs one warning and keeps playing; nothing errors into the loop | ☐ pending |
| 20 | Mobile input | touch device / emulator | STEAL tappable, thumbstick does not jump, no control under the notch | ☐ pending |

Record the results of this table in the change report before publishing.

## 3. Reproducing the automated gate

```bash
python3 tools/bootstrap_luau.py --jobs 4     # first run only (downloads the Luau CLI)
python3 tools/check.py                       # 248 tests + build + export + analysis
python3 tools/artcheck.py                    # 35 art-direction tests alone
python3 tools/verify_place.py                # 36 place-structure tests alone
```

The delivery chain that regenerates every artefact:

```bash
python3 tools/creatures.py && python3 tools/build_place.py && python3 tools/check.py \
  && python3 tools/preview.py && python3 tools/uidraw.py && python3 tools/package_release.py
```
