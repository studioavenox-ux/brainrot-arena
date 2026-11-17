# HOTFIX 01 — Critical HUD startup failure

Status: **fixed in source, covered by regression tests, gate green.**
**Not yet Studio-verified.** The only evidence that closes this defect is a new
Roblox Studio Play test that builds the HUD. See [Verification](#5-verification-required).

## 1. What happened

This was the first real engine result in the project's history — every previous
phase was verified against a mock of the Roblox API, never against Roblox itself.

A Studio Play test reported:

```
__hovered is not a valid member of TextButton
  at PlayerGui.BrainrotHUD.SafeArea.TopHud.Specimens
```

HUD construction aborted at the first button. The game had no interface.

## 2. Root cause

`src/client/Kit.luau`, inside `Kit.button`, line 252:

```lua
button.__hovered = function() return hovered end
```

Roblox Instances are not Lua tables. They expose exactly the members their class
defines, and assigning anything else raises
`<name> is not a valid member of <Class>` at the assignment, not at first use. So
the very first `Kit.button` call — the `Specimens` button, the first interactive
control built in `TopHud` — terminated HUD construction.

Three further facts made this fail silently for its whole life:

- the local `hovered` was **write-only**. Set at line 221, `true` on MouseEnter,
  `false` on MouseLeave, and read by nothing except the closure being stored.
  The hover *visuals* never used it; they lived in the two connections as direct
  property writes and tweens.
- the closure therefore changed no behaviour at all. Deleting it removes dead
  code, not a feature.
- the mock permitted it (§3), so 361 passing tests said nothing about it.

## 3. Why the test suite missed it

`tests/roblox_mock.luau`, `instanceMt.__newindex`:

```lua
if string.sub(key, 1, 1) == "_" then rawset(obj, key, value); return end
assert(propertyExists(obj._class, key), "Unknown property " .. obj._class .. "." .. key)
```

The mock validated property writes against the real API schema in
`tests/fixtures/roblox-api.json` — but a blanket `_`-prefix escape hatch let any
underscore-prefixed key through untouched. `__hovered` starts with `_`. The one
rule meant to let the mock keep its own bookkeeping on the Instance also disabled
validation for an entire namespace, and the bug landed exactly there.

This is the important finding of the hotfix: the suite was not missing a test,
it had a hole in its oracle. A mock that says yes to everything proves nothing.

## 4. The fix

### 4.1 Source (`src/client/Kit.luau`)

Removed the four dead lines: `local hovered = false`, the two writes in the
MouseEnter/MouseLeave connections, and the `button.__hovered` assignment.

**Preserved, unchanged:**

| Behaviour | Where |
| --- | --- |
| Hover animation: scale to 1.03, text/accent/background recolour | `button.MouseEnter` |
| Un-hover: scale to 1.0, background restored | `button.MouseLeave` |
| Click: scale to .96, `task.delay`, invoke `onClick` | `button.Activated` |
| Reduced-motion short-circuits | all three, via `o.reducedMotion` |

The hover effect is intact — it was never implemented through the removed
closure. No UI was redesigned; no style, layout or colour changed.

### 4.2 Test oracle (`tests/roblox_mock.luau`)

The blanket `_` rule is replaced by a closed allowlist of the fields the mock
actually owns:

```
_props _children _signals _attributes _propertySignals _destroyed _class
_sourcePath _type _pivot _droppedPivots _played
```

Every other key — underscore or not — is validated against the class schema and
raises with the engine's own message, `"<key> is not a valid member of <Class>"`.
The allowlist was derived by scanning the mock for the fields it really reads and
writes; `_sourcePath` and `_type` were caught by the suite failing immediately
after the change, which is the intended behaviour.

### 4.3 Static audit (`tools/audit_properties.py`, new)

Runtime coverage only reaches the paths a test executes. This check is static:
it finds every instance creation (`Kit.instance`, `Instance.new`, `Kit.button`,
`Kit.panel`, `Kit.text`, …) and validates every property assigned to that binding
against the same schema. It is wired into `tools/check.py` as
**`No invalid custom Instance properties`**, so it runs on every build.

Scoping matters for trustworthiness: a binding is only treated as an Instance
inside the function that created it, and loop variables and plain locals shadow
it. An earlier unscoped version reported `card.amount`/`card.seen` in
`Collection.luau` as invalid — those are fields on a returned wrapper table, not
on the `Frame`. A check that cries wolf gets disabled, so the false positive was
fixed rather than suppressed.

## 5. Regression tests

Added to `tests/adapters.spec.luau`:

| Test | Pins |
| --- | --- |
| `HF-01` | `Kit.button` builds a `TextButton` + `TextLabel`; `__hovered` is absent; no function-valued property exists on the instance |
| `HF-02` | MouseEnter tints the background to `hoverColor`, MouseLeave restores it (hover behaviour preserved) |
| `HF-03` | `Activated` calls the handler exactly once per activation |
| `HF-04` | The mock itself rejects `button.__hovered = fn` with the engine's message, rejects other non-members and caller-owned underscore fields, and still accepts real members |
| `HF-05` | The full client builds; `TopHud.Specimens` exists; every property on every descendant of `game` is non-function |

`HF-04` is the guard against the gap reopening: if the mock ever accepts
arbitrary keys again, it fails.

### Proof the nets work

Both were checked against the broken code, not just the fixed code.

| Scenario | Result |
| --- | --- |
| Broken `Kit.luau` + hardened mock | **36 failures**, incl. `__hovered is not a valid member of TextButton` |
| Broken `Kit.luau` + audit | `Kit.luau:220: button.__hovered is not a valid member of TextButton`, exit 1 |
| Fixed `Kit.luau` + hardened mock | 145/145 pass |
| Fixed `Kit.luau` + audit | clean, exit 0 |

`HF-04` on the *old* mock also fails (`true ~= false`) — the mock accepted the
assignment, which is the missed defect reproduced as a test.

## 6. Audit of all UI creation paths

- **Source:** `tools/audit_properties.py` over all 29 files in `src/` — clean.
- **Runtime:** `HF-05` builds server, HUD and effects, then walks every
  descendant of `game`. No property on any instance holds a function.

`Kit.button` is the shared constructor for `Hud.luau`, `Panels.luau` and
`Collection.luau`; it was the only site with the defect, and it is now covered by
both nets.

## 7. Gate results

`python3 tools/check.py`:

```
PASS Studio place exports built
PASS All 32 Luau files compile
PASS Strict type analysis: authority modules + configuration
PASS No invalid custom Instance properties
PASS Core rules and 100 simulated 12-player rounds
PASS Production adapters against mocked Roblox services
PASS Place structure, loadable API properties and geometry
PASS Art direction: palette, hierarchy, legibility, lighting rig
PASS Deterministic export rebuild
PASS Git diff whitespace check

366 tests passed; 0 failed.
```

361 before, +5 regression tests. Deterministic export rebuild unchanged.

## 8. Verification required

**The defect is not closed until a new Studio Play test builds the HUD.** Nothing
in this repository can prove that; the mock is not the engine.

1. Open `artifacts/BrainrotArena-Project.zip` (or the `.rbxlx` in `places/`) in
   Roblox Studio.
2. **Play** (`F5`). The HUD must appear: top bar with the specimen counter,
   timer and stage label; the `Specimens` button among the top controls.
3. Confirm no output line reads `is not a valid member of`.
4. Hover the `Specimens` button — it must scale up and tint; move off — it must
   return. Click it — the collection panel must open.
5. Record the result. A pass closes Hotfix 01; a failure reopens it with the new
   message, and the mock now raises the same error at the same call.

## 9. Files changed

| File | Change |
| --- | --- |
| `src/client/Kit.luau` | remove dead hover state and the invalid `__hovered` assignment |
| `tests/roblox_mock.luau` | closed internal allowlist; non-members raise the engine message; `env:sandbox` helper for datatype-using tests |
| `tests/adapters.spec.luau` | 5 hotfix regression tests (140 → 145) |
| `tools/audit_properties.py` | new static audit, run by the gate |
| `tools/check.py` | wire the audit in as `No invalid custom Instance properties` |
| `docs/KNOWN_LIMITATIONS.md` | new entry: mock coverage cannot substitute for engine runs |
| `docs/HOTFIX_01_HUD_STARTUP.md` | this report |

## 10. What this does not establish

- The HUD is **not** confirmed working in Roblox. Only §8 can do that.
- Everything else stays as it was: persistence, shutdown drain, multiplayer,
  touch and the mobile two-row layout remain **BLOCKED/unverified** in the engine
  (rows `S-01`, `7B-D1`, `7C-D1` and the `7C` manual matrix).
- No Phase 8 work, no gameplay changes.
