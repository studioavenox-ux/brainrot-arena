# Dynamic audio

Status: **implemented and covered by headless tests. Not heard in Roblox Studio or on a device yet.**
No sound IDs are bundled, and none have been invented.

## What plays and when

| Game state | Music track | Stingers (one-shot cues) |
|---|---|---|
| Waiting, Intermission, Results | `Lobby` | `RoundEnd` when a round finishes |
| Playing, no Chaos Event | `Arena` | `RoundStart` when a round starts |
| Playing, Chaos Event active | `Chaos` (dramatic) | `ChaosStart` on the event's first frame, `ChaosEnd` when it closes |

- Music changes **crossfade**. Each track fades to its target over `Audio.CrossfadeSeconds` (1.5 s). The
  fade is a fixed volume step per frame, so every fade takes the same wall-clock time.
- Stingers fire only on **edges**. A player who joins mid-round or mid-event hears the current
  music but no stinger for something that already began.
- The **Settings → Sound** toggle mutes music and cues together. Turning it off fades the music out
  and silences cues at once. The Settings label reads "Sound and music".
- Audio is **never authoritative**. It reads the replicated snapshot. Nothing audio does can change
  rewards, timing or gameplay.

## Configuration: `src/shared/Config.luau` → `Config.Audio`

Every slot defaults to `""`, which means **silent**. A silent slot creates no `Sound` at all.

| Key | Meaning |
|---|---|
| `CrossfadeSeconds` | Fade time between music tracks. |
| `MusicVolume` | Loudest level for a music track (0–1). |
| `CueVolume` | Level for one-shot cues (0–1). |
| `Tracks.Lobby` | Music ID for the lobby. |
| `Tracks.Arena` | Music ID for normal play. |
| `Tracks.Chaos` | Music ID for the Chaos Event. |
| `Cues.RoundStart` / `RoundEnd` | Round stingers. |
| `Cues.ChaosStart` / `ChaosEnd` | Chaos Event stingers. |
| `Cues.Steal` | Reserved. Not yet wired to the steal path. |
| `Cues.Ability` | Reserved generic ability cue. |

### How to fill a slot

1. Use an audio asset you **own or are licensed to use**.
2. Paste its ID as a string in the form `"rbxassetid://<number>"`.
3. Leave the slot as `""` if you have no asset. The game still runs.

Malformed IDs fail loudly. `Audio.new` asserts on a bad track ID, and `AudioRules.cueId` asserts on a bad
cue ID, so a typo never silently plays nothing.

## Ability sound cues (API only)

No playable abilities exist yet, so there are no ability sounds. The cue API is in place:

- `Audio.cue(controller, name)` plays `Config.Audio.Cues[name]` and returns `true` only when a sound
  actually started. It returns `false` for an empty slot or while Sound is off.
- An **unknown** cue name is an error. `AudioRules.cueId` asserts on it, so a typo cannot fail silently.
- When abilities land, add one key per ability to `Config.Audio.Cues`, for example `"Ability.Dash"`,
  and call the cue from the ability's client handler. The server's ability decisions do not depend on it.

## Cleanup

- `Audio.destroy` removes the `BrainrotAudio` folder and every Sound in it.
- One-shot cue Sounds are destroyed by `Debris` after 8 seconds.
- A track with no configured ID is never created, so there is nothing to clean up for it.

## Code map

| File | Role |
|---|---|
| `src/shared/AudioRules.luau` | Pure rules: track choice, fade step, ID validation, cue lookup. Covered by `tests/core.spec.luau`. |
| `src/client/Audio.luau` | Roblox layer: creates Sounds, follows the state, runs fades, plays cues, cleans up. Covered by `tests/adapters.spec.luau` on the mock. |
| `src/client/Main.client.luau` | Creates the controller, feeds it state, ticks it per frame, destroys it on shutdown. |

## Not verified

- Actual playback, loudness, mixing, and whether crossfades sound smooth. These need a Studio and device pass.
- Licensing and content of any music or sound asset you choose.
- Behaviour on Android hardware and under real network latency.
