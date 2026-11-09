#!/usr/bin/env python3
"""Build, compile, analyze, execute tests, verify exports, and write an honest build report."""
from __future__ import annotations
import argparse
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from world import make_world  # noqa: E402
ARTIFACTS = ROOT / "artifacts"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau-bin", type=Path, default=ROOT / ".tools/luau-0.744")
    parser.add_argument("--check-generated", action="store_true", help="Fail if committed/generated exports were stale before the build")
    args = parser.parse_args()
    binaries = {}
    for name in ("luau", "luau-compile", "luau-analyze"):
        candidate = args.luau_bin / name
        binaries[name] = str(candidate) if candidate.is_file() else shutil.which(name)
        if not binaries[name]:
            raise SystemExit("Luau tooling not found. Optional developer setup: python3 tools/bootstrap_luau.py. Studio users need only the .rbxlx file.")
    ARTIFACTS.mkdir(exist_ok=True)
    generated = [ROOT / "src/server/WorldData.luau", *sorted((ROOT / "places").glob("*.rbxlx"))]
    before = {str(p): digest(p) for p in generated if p.exists()}
    stages = []

    def run(key, title, command):
        result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (ARTIFACTS / f"check-{key}.log").write_text(result.stdout, encoding="utf-8")
        print(f"{'PASS' if result.returncode == 0 else 'FAIL'} {title}", flush=True)
        stages.append({"name": title, "passed": result.returncode == 0})
        if result.returncode:
            print(result.stdout)
            raise SystemExit(result.returncode)
        return result.stdout

    py = sys.executable
    run("build", "Studio place exports built", [py, "tools/build_place.py"])
    if args.check_generated:
        stale = [p for p, value in before.items() if digest(Path(p)) != value]
        if stale:
            raise SystemExit("Generated files were stale: " + ", ".join(stale))
    files = sorted([*ROOT.glob("src/**/*.luau"), *ROOT.glob("tests/**/*.luau")])
    run("compile", f"All {len(files)} Luau files compile", [binaries["luau-compile"], "--null", *map(str, files)])
    core = sorted(ROOT.glob("src/server/core/*.luau")) + [ROOT / "src/shared/Config.luau", ROOT / "src/shared/AudioRules.luau"]
    run("analyze", "Strict type analysis: authority modules + configuration", [binaries["luau-analyze"], *map(str, core)])
    core_output = run("core", "Core rules and 100 simulated 12-player rounds", [binaries["luau"], "tests/core.spec.luau"])
    adapter_output = run("adapters", "Production adapters against mocked Roblox services", [py, "tools/test_adapters.py", "--luau", binaries["luau"]])
    xml_output = run("place", "Place structure, loadable API properties and geometry", [py, "tools/verify_place.py"])
    art_output = run("art", "Art direction: palette, hierarchy, legibility, lighting rig", [py, "tools/artcheck.py"])
    hashes_before = {str(p): digest(p) for p in generated}
    run("deterministic", "Deterministic export rebuild", [py, "tools/build_place.py"])
    assert all(digest(Path(p)) == value for p, value in hashes_before.items()), "Non-deterministic generated output"
    run("whitespace", "Git diff whitespace check", ["git", "diff", "--check"])

    core_count = int(re.search(r"CORE RESULTS: (\d+) passed, 0 failed", core_output)[1])
    adapter_count = int(re.search(r"ADAPTER RESULTS: (\d+) passed, 0 failed", adapter_output)[1])
    place_count = int(re.search(r"Ran (\d+) tests", xml_output)[1])
    art_count = int(re.search(r"Ran (\d+) tests", art_output)[1])
    counts = {"core_luau": core_count, "mock_adapter_luau": adapter_count,
              "place_python": place_count, "art_direction_python": art_count}
    source_hash = hashlib.sha256()
    for path in sorted(ROOT.glob("src/**/*.luau")):
        source_hash.update(path.relative_to(ROOT).as_posix().encode())
        source_hash.update(path.read_bytes())
    places = {p.name: {"bytes": p.stat().st_size, "sha256": digest(p)} for p in sorted((ROOT / "places").glob("*.rbxlx"))}
    verified_at = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    report = {
        "verified_at_utc": verified_at, "status": "automated_checks_passed_studio_unverified",
        "test_counts": counts, "total_passed": sum(counts.values()), "failed": 0,
        "luau_files_compiled": len(files), "source_sha256": source_hash.hexdigest(),
        "static_world_parts": len(make_world()["Parts"]), "pickup_slots": 48,
        "places": places, "stages": stages,
        "not_executed": ["Roblox Studio import", "Roblox client/server multiplayer simulation", "Engine physics and rendering", "Real touch-device input", "Bundled sound playback", "Dynamic music and cue playback", "Chaos Event in Studio", "Published server test"],
    }
    (ARTIFACTS / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# BRAINROT ARENA — prototype build report", "", f"Verified: **{verified_at}**.", "",
        "**Automated checks passed. Roblox Studio / engine acceptance is still unverified.**",
        "This Linux workspace has no Roblox Studio installation or Roblox control connector.", "",
        "## Delivered", "",
        "- Two self-contained Studio-openable `.rbxlx` exports, plus editable Luau source and an optional Rojo project.",
        "- Redesigned tropical lobby/arena: 906 anchored parts (824 map + 82 Phase 5 event parts;",
        "  913 instances incl. 7 baked sign boards), four connected satellite platforms, and 48",
        "  collectible slots.",
        "- 12-second intermission → **180-second staged round** → 9-second results; repeat automatically.",
        "  Stages: Collect 0 s / Compete 45 s / Chaos 105 s / Final Rush 150 s, each boundary banking",
        "  every player's carried cells.",
        "- Atomic server pickups (+1/+5/+10), synchronized HUD/leaderboard, late joins, respawns and fall rescue.",
        "- **Stealing:** one argument-free `Steal` verb resolved entirely on the server — nearest rival",
        "  within 13 studs, 8-second cooldown, 3-second spawn protection, 4-second victim immunity,",
        "  12-second no-repeat window; moves one *carried* cell and never touches banked score.",
        "- **One Chaos Event per round**, exactly 35 s, drawn server-side from four kinds (Low Gravity,",
        "  Bouncy World, Slippery Chaos, Brain Cell Rush) that never overlap another event. It opens at",
        "  105 s in the normal round (6 s warning) and at 8 s in QuickTest (50 s round, 3 s warning). Each",
        "  kind is cleaned up at 35 s. See [CHAOS_EVENTS.md](CHAOS_EVENTS.md).",
        "- **Dynamic audio** (configured, silent by default): lobby, arena and Chaos music that crossfade,",
        "  round and Chaos stingers, one Sound setting, and an ability-cue API. No sound IDs are bundled.",
        "  See [AUDIO.md](AUDIO.md).",
        "- Winner/tie/no-score announcements; **persistent** coins, specimen log, lifetime stats and the",
        "  server-validated Pulse Halo in a DataStore profile with a documented memory fallback. See",
        "  [PHASE5_STEAL_AND_EVENTS.md](PHASE5_STEAL_AND_EVENTS.md).",
        "- Server-authoritative arena access: heartbeat routing with verified pivots, backoff and a",
        "  seated/dead-safe fallback, so a round always pulls every eligible player in and returns",
        "  them afterwards. See [PHASE3_GAMEPLAY_FIXES.md](PHASE3_GAMEPLAY_FIXES.md).",
        "- Complete game UI on a generated design system: top HUD (cells, coins, synchronized clock),",
        "  live leaderboard, centre notifications (phase, chaos event, winner/tie), bottom Shop/Gear/",
        "  Settings cards acting on real server data, lobby countdown; responsive from phone to",
        "  desktop with reduced-motion and SFX preferences. The phone top bar is derived rather",
        "  than hard-coded (coin chip sized first, clock takes what is left, the specimen and",
        "  RANKS chips stack under it, message bands take the corridor or stack below), so no",
        "  two controls can collide on a 320 pt-wide screen. See",
        "  [UI_IMPLEMENTATION_PHASE3.md](UI_IMPLEMENTATION_PHASE3.md) and `docs/previews/ui-*.jpg`.",
        "- Visual redesign: natural sand/teal/stone palette, tropical greens, soft blue sky with a",
        "  warm 15:20 sun, authored materials and shadows, redesigned gate/signage, rarity",
        "  silhouettes. Gameplay rules and walkable geometry are unchanged. See",
        "  [VISUAL_CHANGES.md](VISUAL_CHANGES.md) and the renders in `docs/previews/`.",
        "- Six original characters as real, separate Roblox Models — BRAINY (brain, Common, +1),",
        "  BLORBO (frog, Common, +1), GLORP (fish, Rare, +5), HJONK (goose, Rare, +5), CRUSTY",
        "  (toast, Legendary, +10), WHIFFERS (sock, Legendary, +10) — procedurally built from",
        "  primitives, baked into `Workspace.BrainrotCharacters` in both places as editable models",
        "  on plinths with floating name/rarity cards, and instantiated at runtime for the 48 cells.",
        "  Per-character idle and collect animation, pickup burst, and a collection screen of six",
        "  live viewports. Server owns the species roll and the reward. See",
        "  [CHARACTERS_PHASE4.md](CHARACTERS_PHASE4.md) and `docs/previews/cast.jpg`.",
        "- Event-only raft and path geometry from earlier builds stays in the export, inert at rest",
        "  (non-colliding), and is no longer scheduled. Rendered previews: `docs/previews/events.jpg`",
        "  (three orbit rafts and four vanishing spans, drawn at rest, non-colliding).", "",
        "## Checks actually executed", "", "| Check | Result |", "|---|---:|",
        f"| Luau core tests (100 × 12-player round simulations + steal / stage / event rules) | {core_count} passed |",
        f"| Real server/client scripts against mocked Roblox services (+ steal and persistence) | {adapter_count} passed |",
        f"| XML/API/geometry export tests | {place_count} passed |",
        f"| Art-direction gate (palette, hierarchy, legibility, lighting) | {art_count} passed |",
        f"| Official Luau compilation | {len(files)} files passed |",
        "| Strict analysis | authority modules, ChaosRules, AudioRules and Config passed |",
        "| Repeat build | Byte-for-byte deterministic |", "| Git whitespace check | Passed |", "",
        "The headless adapter tests validate code contracts, not Roblox physics, actual networking, UI rendering, or audio.",
        "`docs/previews/*.jpg` are software renders of the same geometry/colour tables (tools/preview.py),",
        "not engine captures; rendered lighting and materials still need the Studio pass.", "",
        "## Remaining acceptance work", "",
        "Open `places/BrainrotArena-QuickTest.rbxlx` in Roblox Studio and use its Test tab to start **2 clients**.",
        "Confirm both players are pulled into the arena (including from a seated character), collecting,",
        "jumping during low gravity, the winner card, the Shop purchase, and the next round on both clients.",
        "Then walk the lobby exhibit (all six characters should be visible, named and animating), press",
        "**C** to open the specimen log, catch one of each species, and confirm the log fills to 6 / 6",
        "",
        "Phase 5 adds a hands-on pass that cannot be automated: stand two clients within 13 studs and",
        "tap **STEAL** (one carried cell should change hands and both clients should be told), press it",
        "again to see the 8-second refusal, tag a freshly respawned player to see `PROTECTED`, watch a",
        "stage boundary bank the carried cells, and watch the Chaos Event warn, run for 35 s and clean up. The full",
        "20-row matrix is in [TEST_REPORT_PHASE5.md](TEST_REPORT_PHASE5.md).",
        "",
        "Use Device Emulator to verify touch controls/text and check Output for errors. See [TESTING.md](TESTING.md).",
        "No code pasting, plugin installation, API keys, asset uploads, or monetization setup is required.", "",
        "## Deliberate limits", "",
        "- One map. The Chaos kind is drawn at random once per round from a pool of four.",
        "- Stealing auto-targets the nearest eligible rival; there is no target picker (one tap on a phone).",
        "- No cross-server session locking on profiles: two servers writing one player at the same moment",
        "  resolve last-write-wins. See [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).",
        "- Movement checks are a basic sanity layer, not a complete exploit-prevention system.",
        "- Bundled pickup tone availability, music and cue playback (no sound IDs are configured yet) and exact visual polish still need the Studio/device pass.", "",
        "## Export integrity", "", f"Source SHA-256: `{source_hash.hexdigest()}`", "",
    ]
    for name, info in places.items():
        lines += [f"- `{name}` — {info['bytes']:,} bytes; SHA-256 `{info['sha256']}`"]
    (ROOT / "docs").mkdir(exist_ok=True)
    (ROOT / "docs/BUILD_REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"\n{sum(counts.values())} tests passed; 0 failed. Studio engine not available, not claimed tested.")
    print("Report: docs/BUILD_REPORT.md | Machine-readable: artifacts/verification.json")


if __name__ == "__main__":
    main()
