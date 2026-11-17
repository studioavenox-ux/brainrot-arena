# Known Limitations — Phase 5

Deliberately not done, or done in a way that has a visible cost. Nothing here is
hidden in the code comments.

## Verification

1. **Roblox Studio was not available.** Every claim in this repository comes from
   the automated gate (329 assertions) plus the offline renderer. The Studio
   acceptance matrix in `docs/TEST_REPORT_PHASE5.md` is **pending**, not passed:
   physics feel, real DataStore latency, mobile touch and the actual look of the
   rafts in the engine have not been observed.
2. **The preview plates are stylised offline renders**, not engine screenshots —
   they say so on every plate.

## Gameplay

3. **Stealing targets the nearest eligible rival automatically.** There is no
   target selection UI; if two rivals are in range the closer one is chosen. This
   is intentional (it keeps the verb to one tap on a phone) but it means a player
   cannot choose *who* to rob when rivals are stacked.
4. **The stolen cell is the victim's largest carried cell**, not a choice by either
   player. Again one rule, easy to read, no menu.
5. **Only one event runs at a time.** The spec asks for five survival events with
   predictable timing; overlapping windows were rejected because two simultaneous
   physics changes make the round unreadable and untestable.
6. **Wildcards rotate deterministically by round id**, so a player who plays many
   rounds will learn the order. This is the price of every client agreeing on the
   schedule.
7. **Slippery terrain is global**, not a zone: `CustomPhysicalProperties` is applied
   to arena surfaces for the window. A per-tile ice field would cost more parts than
   the budget allows.
8. **Moving rafts move by CFrame on the server**, not by physics constraints. That
   is cheap and deterministic, but a player standing on a raft is carried by their
   own character controller rather than by a welded assembly, so very fast motion
   would feel slidey. The orbit is deliberately slow (30 s per lap).
9. **The map grew from 824 to 906 static parts.** The 82 new parts are event
   geometry, all non-colliding at rest. The per-visible-cell cap, the all-cells
   ceiling and the seven-light rule are unchanged; the old 840-part ceiling was
   raised to 920 with an explicit event-geometry budget, and the reason is recorded
   in `tools/artcheck.py` and `tools/verify_place.py`.
10. **Balance is untuned by human play.** Cooldown 8 s, range 13 studs, protection
    3 s, immunity 4 s, repeat window 12 s, and the four stage boundaries are
    reasoned defaults, not the product of playtests.

## Data

11. **No cross-server session locking.** A player who joins a second server at the
    same moment could have the two servers write the same profile; the last write
    wins. Roblox's own `UpdateAsync` semantics would fix this and are mocked but not
    used by the live path yet.
11a. **Persistence is now the default in a live server** (`Persistence.new({})`
    opens the DataStore; Studio stays memory-only unless `persistInStudio` is
    passed). This is a behaviour change from the Phase 5 build, where an inverted
    default meant a published server never wrote a profile at all. Real DataStore
    latency, throttling and quota behaviour are still unverified — see
    [PHASE6_DURABILITY.md](PHASE6_DURABILITY.md) for the reproductions and the
    pending Studio/device checks.
11b. **A failed profile read is not retried forever.** The session gets one
    bounded retry (`Config.PersistenceRetryDelay`); if that also fails the player
    keeps playing with everything unsaved and the real record is left intact. No
    write path exists for that session, so nothing is lost and nothing is gained
    until the next join succeeds. A player who never rejoins while the store is
    healthy keeps only their previously saved progress.
11c. **The phone action bar can overlap the steal and ability panels.** All three
    sit in the same 118 px lift band, and the bar is 252 px wide and centred. The
    steal button stays readable and on top where they cross, but touch
    interception has not been verified on a device (rows T-03/T-04/T-10).
11d. **No `game:BindToClose`.** A player leaving is saved, and every completed
    round is saved at the Results edge, but a server *shutdown* does not wait for
    the final queued write. Coins earned after the last Results edge, and the
    last specimen merge, can be lost on shutdown. Verify with P-06 in
    [PHASE7B_ACCEPTANCE_PACKAGE.md](PHASE7B_ACCEPTANCE_PACKAGE.md).
12. **No purchase ledger.** Cosmetic purchases are coin spends inside the round,
    persisted immediately. There is no audit trail of individual transactions.
13. **Save interval.** Profiles are written on purchase, on leave and on round
    results — not on a fixed timer. A server crash inside a round loses that round's
    coin reward for every player in it (scores are transient by design, so nothing
    already banked is lost).
14. **Nothing is validated against the Roblox economy** because there is no Robux
    or MarketplaceService path; the game is free-to-play and pay-to-win is
    structurally impossible.

## Scope not attempted

15. **No character cosmetics beyond the halo**, no emotes, no shop rotation. The
    spec's progression pillars (persistent cosmetics, coins, stats, emotes) are
    present as *systems* — coins, a persisted cosmetic, lifetime stats — not as a
    content library.
16. **No matchmaking or party system.** 2–12 players share one server and one
    auto-starting round, as in Phase 4.
17. **No spectator camera after being eliminated.** There is no elimination: a
    fallen player is rescued and keeps playing.
