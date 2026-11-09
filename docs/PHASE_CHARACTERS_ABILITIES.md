# Phase: character selection and abilities

Status: **implemented and covered by automated tests. Not yet played in Roblox Studio or on a device.**
Pets and eggs are out of scope for this phase. Secret characters and any Robux pricing are also out of
scope: all six characters are free.

## What was built

- **Six free characters**, one active at a time. Each one is a cell species from `Creatures.luau`, so the
  cast a player collects and the characters they can play are the same six.
- **Switching:** three normal switches per round, usable at any time during `Playing`. One bonus switch,
  usable only during the Chaos Event. Four at most per round. The first character, BRAINY, is active at the
  start and costs nothing.
- **Abilities**, each with its own server-side cooldown per player:

| Character | Ability | Cooldown | Effect (server-side) |
|---|---|---|---|
| BRAINY | Mind Trick | 20 s | Visual decoy: an anchored, non-colliding copy of the caster for 6 s. Never targeted. |
| BLORBO | Belly Bounce | 15 s | Pushes every rival within 10 studs away by 55 studs/s and lifts them 18 studs/s. |
| GLORP | Bubble Dash | 12 s | The caster dashes 70 studs/s along its facing for 0.35 s. |
| HJONK | HONK Wave | 18 s | Rivals within 14 studs walk at 50% speed for 2.5 s. |
| CRUSTY | Toast Launch | 16 s | Rivals within 8 studs are launched straight up at 60 studs/s. |
| WHIFFERS | Sock Snare | 14 s | Rivals within 12 studs walk at 40% speed for 4 s. |

- **Targeting:** automatic. Every participating rival inside the radius is affected. The caster is always
  immune to their own ability.
- **Brain Cells:** abilities, switches and cooldowns never award, steal or move a cell. A test fires every
  ability and compares the scores before and after.

## Architecture

- `src/shared/Config.luau`: `Characters` (order, switch counts, roster, ranges, cooldowns, durations,
  movement margin). Every number is in one place.
- `src/server/core/CharacterRules.luau` (pure): switching quota, Chaos-only bonus, slot validation,
  cooldowns per player and per character, reset at `beginRound`, and refusal reasons.
- `src/server/core/AbilityRules.luau` (pure): target selection, directions, velocities, slow statuses
  (keeps the stronger factor and the later expiry when stacked), and pruning.
- `src/server/AbilityService.luau` (Roblox adapter): turns decisions into velocities, walk speeds, a decoy
  model and grants to `MovementGuard`. It touches no score and no round state.
- `src/server/core/MovementGuard.luau`: `grant(id, speed, untilAt, now)` gives a temporary, exact speed
  allowance for an ability-driven movement. It refuses unknown tracks, so no grant can seed a teleport.
- `src/server/Main.server.luau`: two validated remotes, `Ability` (no arguments, 0.25 s rate limit) and
  `Character` (one integer slot 1–6, 0.25 s rate limit). `CharacterState` sends the server's view back to
  the client, including refusal notices. Victims get a notice too.
- `src/client/Hud.luau`, `src/client/Panels.luau`, `src/client/Main.client.luau`: an Ability button
  (`AbilityButton`), six slot chips (`Slot1`–`Slot6`), a readout (`Readout`), the Q key for the ability, and
  keys 1–6 for switching. The client sends requests only and never decides an effect.
- Name tag: a `CharacterTag` BillboardGui on the Head shows the active character's name.

## Invariants and how they are checked

| Invariant | Check |
|---|---|
| Remotes validate their input | adapter test: extra arguments and bad slots are refused with no effect |
| Quotas, including Chaos-only bonus | core and adapter tests (outside Chaos, bonus refused; in Chaos, used once; never a fifth) |
| Cooldown per character, kept across switches, reset per round | core and adapter tests |
| No Brain Cell change from any ability | adapter test firing all six abilities |
| Caster is never affected | adapter knockback test |
| Movement is granted only for its duration | core grant tests and the dash and knockback adapter tests |
| Respawn clears slows and dashes but keeps cooldowns | adapter respawn test |
| Chaos start and end re-send the character view to everyone | adapter bonus test |

## Decisions (approved by the user)

1. Roster meaning: 3 normal switches plus 1 bonus, maximum 4 switches per round.
2. Unlocks: all six characters are free.
3. Cooldowns are kept for the round only (server memory). They are not stored across sessions.
4. Remotes: a separate `Ability` remote and `Character` remote, each validated on the server.
5. Roster abilities and the ranges and cooldowns in the table above.

## Assumptions to review

- BRAINY is the active character at round start and that first state costs no switch.
- The bonus switch is usable only during the Chaos Event, and normal switches are spent first.
- The decoy is a visual copy with no collision and no targeting. It does not distract the server's
  target selection.
- Characters are told apart by their name tag and ability, not by separate avatar models. Avatar models
  and animations are a later phase.
- All numbers are tuning starting points, not balance decisions.

## Defects found and fixed while testing

- The "NOTHING IN RANGE" notice showed for a single hit. The count check was off by one. It now reports
  the true number of hits.
- The Chaos Event opened without telling the clients, so the bonus switch appeared only on the next
  update. The view is now sent to every player on each Chaos edge.

## Not verified

- Roblox Studio, real physics (knockback, dash and launch feel), device touch input, and multiplayer with
  real clients. The tests run against the mocked Roblox boundary only.
