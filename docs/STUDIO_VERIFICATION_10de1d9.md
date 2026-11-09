# Roblox Studio verification package: commit 10de1d9

Scope: character selection, the six abilities, switch limits, cooldowns, the Chaos bonus switch,
Brain Cell integrity, respawn and disconnect, and mobile touch controls.

**Status: NOT RUN.** Every test in this document is a manual Roblox Studio test. None of them has
passed. Automated results are listed only for reference and are not a substitute for a Studio run.

Commit under test: `10de1d9` (`Character selection and abilities: six free characters, server-validated abilities`).
Automated gate at that commit: `tools/check.py` exit 0, 319 passed (core 145, adapters 103, export 36, art 35).
Mocked-Roblox adapter tests cover the logic below. They do not test engine physics, replication, input, or rendering.

Pets, eggs and Spin the Wheel are out of scope and must not be tested or changed in this pass.

---

## Part 1: Setup

### 1.1 Requirements

- Roblox Studio, signed in, on Windows or macOS. Device Emulator is available from the View menu.
- Optional: a real iPhone or Android device for touch testing, with Studio's "Test on device" option or the Roblox app.
- The ZIP `artifacts/BrainrotArena-Project.zip` from commit `10de1d9`, or a clone of that commit.

### 1.2 Open the place

1. Extract the ZIP. Keep the `BrainrotArena` folder as is.
2. In Studio, choose **File → Open from File…** and open one of:
   - `places/BrainrotArena-QuickTest.rbxlx`: 50 s round. Chaos starts at 8 s, with a 3 s warning. Use this for most tests.
   - `places/BrainrotArena.rbxlx`: 180 s production round. Chaos starts at 105 s, with a 6 s warning. Use this for the timing check.
3. Save the place to a new file so the original is not overwritten.
4. Confirm the Output window shows no errors on load. Warnings about `rbxasset://` URLs are expected. Record any other warning.

### 1.3 Configure multiple clients

1. In the **Test** tab, open the playtest-mode dropdown and choose **Players** (or **Server & Clients**, depending on your Studio version).
2. Set the number of clients: **2** for the two-player tests, **3** for the three-player tests.
3. Press **F5** (or **Play**). Each client is a separate window. Name them Client A, B and C in your notes.
4. Note which window is which before you start. Every expected result below refers to a specific client.

### 1.4 Controls to know

| Action | PC | Mobile / touch |
|---|---|---|
| Use the active ability | **Q** | **Ability** button (`AbilityButton`, bottom bar) |
| Switch character | **1–6** (slot number) | Slot chips **1**–**6** (`Slot1`…`Slot6`) |
| Scoreboard | **Tab** | Tap the leaderboard button |
| Specimen log | **C** | Tap the specimen control |
| Help | **H** | Help control |
| Steal (existing system, not an ability) | **E** | Steal button |
| Shop | **B** | Shop control |

The character strip, the readout and the ability button are in the HUD. The readout (`Readout`) shows the
active character and the switches left.

### 1.5 Server-side notices (what you should read on screen)

These come from the server, and the client only displays them.

| Situation | Notice shown |
|---|---|
| Switch succeeds | `NOW: <CHARACTER TITLE>` |
| Switch outside a live round | `CHARACTERS ARE LIVE DURING PLAY` |
| Not yet in the round | `JOIN THE ROUND FIRST` |
| Slot not 1–6 | `NO SUCH CHARACTER` |
| Already that character | `ALREADY YOUR CHARACTER` |
| No switches left | `NO SWITCHES LEFT THIS ROUND` |
| Bonus switch outside Chaos | `BONUS SWITCH: CHAOS EVENT ONLY` |
| Ability on cooldown | `ABILITY RECHARGING` |
| Ability with no live character | `ABILITY NEEDS A LIVE CHARACTER` |
| Ability hits nobody | `<TITLE> • NOTHING IN RANGE` |
| Ability hits N rivals | `<TITLE> • N HIT` |
| Mind Trick placed | `MIND TRICK • DECOY LIVE` |
| Bubble Dash used | `BUBBLE DASH` |
| Victim of an ability | `<TITLE> HIT YOU` (on the victim's screen) |

---

## Part 2: Character reference

| Slot | Character | Ability | Cooldown | Behaviour (from `Config.Characters`) |
|---|---|---|---|---|
| 1 | BRAINY | MIND TRICK | 20 s | Decoy copy of the caster for 6 s, offset 6 studs. Not targetable. |
| 2 | BLORBO | BELLY BOUNCE | 15 s | Rivals within 10 studs pushed at 55 studs/s, lifted 18 studs/s. |
| 3 | GLORP | BUBBLE DASH | 12 s | Caster dashes 70 studs/s along facing for 0.35 s. |
| 4 | HJONK | HONK WAVE | 18 s | Rivals within 14 studs slowed to 50% for 2.5 s. |
| 5 | CRUSTY | TOAST LAUNCH | 16 s | Rivals within 8 studs launched straight up at 60 studs/s. |
| 6 | WHIFFERS | SOCK SNARE | 14 s | Rivals within 12 studs slowed to 40% for 4 s. |

Base walk speed is 22 studs/s. A 50% slow means 11, and a 40% slow means 8.8.

Switch rules: BRAINY is active at the start of each round and costs nothing. Three normal switches per round.
One bonus switch that works only during the Chaos Event. Four switches at most in total.

---

## Part 3: Test scenarios

Mark each result as **PASS**, **FAIL**, or **BLOCKED** (with the reason). Leave a result empty until you run it.
Use the bug template in Part 5 for any FAIL.

### 3.1 Two-player baseline (QuickTest place, 2 clients)

**Manual.** Setup as in 1.3, with 2 clients.

| # | Step | Expected |
|---|---|---|
| 2P-1 | Both clients join the lobby. | Both see the lobby countdown. Both characters appear. |
| 2P-2 | Wait for the round to start. | Both are pulled into the arena. Both HUDs show a round clock and BRAINY as active. |
| 2P-3 | Each client collects some cells. | Each client's own Brain Cells count goes up. The other client sees the same scores on the leaderboard. |
| 2P-4 | Let the round end. | Both see the results card. Both return to the lobby. |
| 2P-5 | Check the output. | No errors in Output on the server or either client. |

### 3.2 Three-player scenario (QuickTest place, 3 clients)

**Manual.** Setup as in 1.3, with 3 clients.

| # | Step | Expected |
|---|---|---|
| 3P-1 | All three join before the round. | All three are participating. Leaderboard lists three names. |
| 3P-2 | Client A uses BELLY BOUNCE (switch to slot 2 first) with B and C standing within 10 studs. | Both B and C are pushed. Client A's notice reads `BELLY BOUNCE • 2 HIT`. B and C each see `BELLY BOUNCE HIT YOU`. |
| 3P-3 | Client A stands still with B 5 studs away and C 40 studs away. Use BELLY BOUNCE. | Only B is pushed. Client A's notice reads `BELLY BOUNCE • 1 HIT`. C is not moved. |
| 3P-4 | Client B uses HONK WAVE (slot 4). | A and C within 14 studs are slowed. B is not slowed. |
| 3P-5 | A player leaves mid-round. | The other two continue. The leaver is removed from the leaderboard. No errors. |

### 3.3 Character selection and switching

**Manual.** Single client, then repeat with 2 clients to see replication.

| # | Step | Expected |
|---|---|---|
| SEL-1 | Start a round. Read the HUD. | Active character is BRAINY. Readout shows `3` normal switches left and the bonus is not offered. |
| SEL-2 | Press **2**. | Notice `NOW: BELLY BOUNCE` (or the Title for slot 2). Active character changes. Name tag above the head reads `BLORBO`. |
| SEL-3 | Press **2** again. | Notice `ALREADY YOUR CHARACTER`. No switch is spent. |
| SEL-4 | Press **0** or **7**. | Notice `NO SUCH CHARACTER`. No switch is spent. (If the key does nothing, record it.) |
| SEL-5 | Tap slot chip **5** on a phone or the emulator. | Same as SEL-2 for slot 5. |
| SEL-6 | Confirm the name tag. | The name tag above the head updates on every switch. The other client sees the new name tag. |
| SEL-7 | Confirm the readout. | Readout counts down the normal switches after each successful switch. |
| SEL-8 | Press **C** or **Tab** while switching. | Those keys still work. Switching does not break other HUD controls. |

### 3.4 All six ability tests

For each ability: switch to the slot, stand where stated, press **Q** (or tap the Ability button), and
compare with the expected result. Use two clients for the target. Use QuickTest so the round is short.

**Manual for all rows.**

| # | Ability | Setup | Expected |
|---|---|---|---|
| AB-1 | **MIND TRICK** (slot 1) | Caster alone. Press Q. | Notice `MIND TRICK • DECOY LIVE`. In Explorer during Play, `Workspace` contains a model `MindTrick_<caster UserId>`. It is anchored and has no collision. Walking into the decoy does nothing. The decoy disappears after about 6 s. |
| AB-2 | **MIND TRICK**, decoy is not targetable | Client B stands next to the decoy and uses BELLY BOUNCE. | Client B's ability does not count the decoy. The decoy is not reported as a hit. |
| AB-3 | **BELLY BOUNCE** (slot 2) | Target 5 studs away, caster on the ground. Press Q. | Target is pushed sideways and lifted. Caster is not moved. Notice `BELLY BOUNCE • 1 HIT`. Target sees `BELLY BOUNCE HIT YOU`. |
| AB-4 | **BELLY BOUNCE** range | Target 15 studs away. Press Q. | Target is not moved. Notice `BELLY BOUNCE • NOTHING IN RANGE`. |
| AB-5 | **BUBBLE DASH** (slot 3) | Caster on the ground facing a direction. Press Q. | Caster moves quickly in the facing direction for about 0.35 s, then stops. Notice `BUBBLE DASH`. Caster is not pushed sideways. |
| AB-6 | **BUBBLE DASH** not into walls/ground | Dash toward a wall. | Caster stops at the wall. No teleport through geometry. (Record what happens. Physics may differ from the mock.) |
| AB-7 | **HONK WAVE** (slot 4) | Target within 14 studs. Press Q. | Target walks at about half speed for about 2.5 s, then returns to normal. Caster keeps normal speed. Notice `HONK WAVE • 1 HIT`. |
| AB-8 | **HONK WAVE** out of range | Target 20 studs away. | Target keeps normal speed. Notice `HONK WAVE • NOTHING IN RANGE`. |
| AB-9 | **TOAST LAUNCH** (slot 5) | Target within 8 studs. Press Q. | Target is launched straight up. Little or no sideways motion. Notice `TOAST LAUNCH • 1 HIT`. |
| AB-10 | **SOCK SNARE** (slot 6) | Target within 12 studs. Press Q. | Target walks at about 40% speed for about 4 s. Caster keeps normal speed. Notice `SOCK SNARE • 1 HIT`. |
| AB-11 | Caster is never hit | Caster uses any ability with nobody nearby. | Caster's own speed, position and score are unchanged. |
| AB-12 | Auto-targeting of all in range | 3 players in range of a radius ability (Belly Bounce or Honk Wave). | Every in-range rival is affected. Count matches the notice. |

### 3.5 Cooldowns and switch limits

**Manual.** Use QuickTest for timing. Use a stopwatch.

| # | Step | Expected |
|---|---|---|
| CD-1 | Press Q with BRAINY. Press Q again immediately. | Second press shows `ABILITY RECHARGING`. |
| CD-2 | Wait about 20 s (BRAINY cooldown). Press Q. | Ability fires. Accept +/- 1 s of tolerance from the server clock. |
| CD-3 | Use BELLY BOUNCE (15 s). Switch to BUBBLE DASH (slot 3). Press Q. | BUBBLE DASH fires at once. Cooldowns are independent per character. |
| CD-4 | Switch back to BELLY BOUNCE (slot 2) before its 15 s ends. Press Q. | `ABILITY RECHARGING`. Switching does not reset the cooldown. |
| CD-5 | Keep spamming Q. | No more than one ability per 0.25 s rate limit. No errors. |
| CD-6 | Use three normal switches (slots 2, 3, 4). Try a fourth normal switch (slot 5). | Fourth switch shows `NO SWITCHES LEFT THIS ROUND`. |
| CD-7 | Let the round end. Start the next round. | Cooldowns reset. Switches reset to three normal. Active character returns to BRAINY. |
| CD-8 | Confirm CD-1 again in the new round. | First Q fires. Cooldowns were cleared at round start. |

### 3.6 Chaos bonus-switch verification

**Manual.** Use QuickTest. Chaos starts at 8 s and lasts 35 s, so it runs from about 8 s to 43 s of the round.

| # | Step | Expected |
|---|---|---|
| CH-1 | Before Chaos starts, use all three normal switches. Press a fourth slot key. | `BONUS SWITCH: CHAOS EVENT ONLY`. No switch is spent. The readout does not offer a bonus. |
| CH-2 | Wait for the Chaos Event warning, then the event. | Readout now offers 1 bonus switch. Both clients see the same state. |
| CH-3 | During Chaos, press a slot key. | Switch succeeds. Notice `NOW: <TITLE>`. Bonus is now used. |
| CH-4 | During Chaos, try a further switch. | `NO SWITCHES LEFT THIS ROUND`. Four total switches, never a fifth. |
| CH-5 | Chaos ends (about 43 s). Press a slot key. | Switch is refused (`NO SWITCHES LEFT THIS ROUND` or `BONUS SWITCH: CHAOS EVENT ONLY` depending on counts). Bonus is not returned after Chaos. |
| CH-6 | Check both clients at the Chaos start and end. | Both show the bonus appearing and disappearing at the same moment (within about 1 s). This tests the fix for the view push. |

### 3.7 Brain Cell score integrity

**Manual.** Read the Brain Cells value from the leaderboard and from `leaderstats` in Explorer
while the round runs. Note values before and after each step.

| # | Step | Expected |
|---|---|---|
| SC-1 | Record Brain Cells (carried and banked) for each client. Use every ability once, one per character, with a rival in range. | No ability changes any client's Brain Cells. |
| SC-2 | Repeat SC-1 with character switches in between. | Switches do not change Brain Cells. |
| SC-3 | Stand in range of a rival who holds cells. Use BELLY BOUNCE and TOAST LAUNCH. | The rival keeps every cell. Abilities do not steal. |
| SC-4 | Collect a cell, then use an ability. | Collected cell count is unchanged by the ability. |
| SC-5 | Check the round results. | Score equals the cells collected by normal play. No ability bonus is visible. |

Note: the Steal verb is a separate, existing system. Use it only in a separate test, and do not count it as an ability
result.

### 3.8 Respawn and disconnect

**Manual.**

| # | Step | Expected |
|---|---|---|
| RS-1 | Set a slow on Client B (HONK WAVE from A). Reset B's character (Roblox Reset). | After respawn, B walks at full speed. The slow is cleared. |
| RS-2 | Use a dash (GLORP), then reset before it ends. | Dash stops. Caster does not carry momentum into the new body. |
| RS-3 | Use BRAINY (decoy), then reset. | The decoy is removed when the character is respawned or the round ends. No leftover `MindTrick_` model stays in Workspace. |
| RS-4 | Use an ability, then reset. Check the ability button and cooldown. | Cooldown is kept after respawn. Pressing Q shows `ABILITY RECHARGING` if it is still running. |
| RS-5 | Respawn mid-round and confirm the name tag. | Name tag is shown on the new character with the active name. |
| RS-6 | Client B leaves mid-round after being hit by a slow. | No errors on the server. A's slots still work. B is removed from the leaderboard. |
| RS-7 | Client B leaves during Chaos holding the bonus switch. Rejoin later. | The rejoining player starts a fresh round state (no leftover switches or cooldowns from the old session). |
| RS-8 | Server stops or client crashes. | Record Output. No infinite loop or runaway error. |

### 3.9 Mobile touch controls

**Manual.** Use the Device Emulator first (View → Device Emulator, choose a phone). Then, if possible,
test on a real phone (Studio "Test on device" or the Roblox app).

| # | Step | Expected |
|---|---|---|
| MT-1 | Open the arena in a phone-sized emulator. | Ability button, slot chips 1–6 and the readout are on screen. None is clipped. |
| MT-2 | Tap the Ability button. | Ability fires once per tap. Notice updates. |
| MT-3 | Tap slot chips 1–6 one at a time. | Each tap switches character, subject to the same rules as 3.3. |
| MT-4 | Tap the Ability button repeatedly. | Rate limit and cooldown apply. No double firing. |
| MT-5 | Check overlaps. | Ability button, slot chips, leaderboard and the Steal button do not overlap on a 320 pt-wide screen. |
| MT-6 | Rotate to landscape. | Layout still usable. Buttons still tappable. |
| MT-7 | Check the readout text. | Text is readable and not truncated (for example `BELLY BOUNCE`). |
| MT-8 | Tap while the joystick is in use. | Ability press does not move the character in an unintended way. |

Device-only checks: touch-target size (aim for comfortably tappable), and whether the Ability button is
still reachable with one thumb. Record actual device model and OS.

### 3.10 Automated checks already in the repo (reference only)

These run without Studio. They are listed so you know what is already covered. They do not replace
the manual tests above.

- Core: `tests/core.spec.luau` (145 passed at 10de1d9). Includes character rules, quotas, cooldowns and grants.
- Adapter: `tests/adapters.spec.luau` (103 passed at 10de1d9). Includes remote validation, ability effects,
  Brain Cell invariance, name tag, HUD keys, and respawn clearing slows. Mocked Roblox only.
- Gate: `python3 tools/check.py` (319 passed at 10de1d9).

---

## Part 4: Pass / fail summary template

| Section | Tests | Pass | Fail | Blocked | Notes |
|---|---|---|---|---|---|
| 3.1 Two-player | 5 | | | | |
| 3.2 Three-player | 5 | | | | |
| 3.3 Selection | 8 | | | | |
| 3.4 Abilities | 12 | | | | |
| 3.5 Cooldowns and limits | 8 | | | | |
| 3.6 Chaos bonus | 6 | | | | |
| 3.7 Brain Cell integrity | 5 | | | | |
| 3.8 Respawn and disconnect | 8 | | | | |
| 3.9 Mobile touch | 8 | | | | |

Studio version: ______  Place opened: ______  Commit: 10de1d9  Tester: ______  Date: ______

---

## Part 5: Bug report template

Copy this for each issue.

```
Title: <short description, for example "HONK WAVE slows the caster">
Test ID: <for example AB-7>
Commit: 10de1d9
Place: <QuickTest or production>
Studio version: <from Help → About>
Device / emulator: <PC/Mac, or phone model and OS>
Clients: <count, and which client was which>

Steps to reproduce:
1.
2.
3.

Expected result:
<exact text from this document, or the behaviour described>

Actual result:
<what happened, exact notice text if any>

Frequency: <always / sometimes (n of m) / once>
Output window errors: <paste any red or yellow lines>
Screenshot or video: <path or link>
Notes: <anything else, for example latency or the other client's view>
```

---

## Part 6: Exit criteria

The Studio pass is complete only when every row in Part 4 is filled in with a real result.
Do not mark a test PASS from automated results. Any FAIL is a bug to fix before the next phase.
Balance values (cooldowns, ranges, slow factors) are starting points, so a test showing a feel problem
should be recorded as a tuning note, not as a functional failure, unless the stated behaviour is wrong.
