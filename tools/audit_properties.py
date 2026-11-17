#!/usr/bin/env python3
"""Fail if any source file assigns a property an Instance does not have.

Roblox Instances only accept real API members. Assigning anything else raises
    <name> is not a valid member of <Class>
and aborts whatever was being constructed -- which is how Hotfix 01 broke HUD
startup with `button.__hovered = function() ... end` on a TextButton.

The adapter tests catch this at runtime for the code paths they execute. This
check is static and covers every file, including paths no test builds.

How it works: find each instance creation (`Kit.instance("Frame")`,
`Instance.new("Part")`, `Kit.button(...)`), then verify every property assigned
to that binding against the class schema in tests/fixtures/roblox-api.json.

Known limitation, printed so it is not mistaken for full coverage: this is a
lexical check over one binding name, so it cannot follow an instance through a
function boundary or distinguish a wrapper table that happens to share the name.
The runtime check in tests/adapters.spec.luau (HF-04/HF-05) is the stronger net
for anything a test actually builds.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "tests/fixtures/roblox-api.json"

# Constructor helpers that return an Instance, mapped to the class they build.
# `None` means the class is given as the first string argument.
CONSTRUCTORS = {
    "Kit.instance": None,
    "Instance.new": None,
    "Kit.panel": "Frame",
    "Kit.scrim": "Frame",
    "Kit.text": "TextLabel",
    "Kit.stroke": "UIStroke",
    "Kit.corner": "UICorner",
    "Kit.gradient": "UIGradient",
}

# Property names that are always valid because they belong to Object.
# (Object properties are in the schema, but this documents the assumption.)


def class_members(schema: dict, cls: str) -> set[str]:
    members: set[str] = set()
    seen: set[str] = set()
    while cls and cls not in seen:
        seen.add(cls)
        definition = schema["Classes"].get(cls)
        if not definition:
            break
        members |= set(definition.get("Properties", {}))
        members |= set(definition.get("Methods", {}))
        cls = definition.get("Superclass")
    return members


def strip_comment(line: str) -> str:
    """Drop a trailing `--` comment so commented-out assignments are ignored."""
    out = []
    i = 0
    in_string = False
    quote = ""
    while i < len(line):
        ch = line[i]
        if in_string:
            out.append(ch)
            if ch == quote and (i == 0 or line[i - 1] != "\\"):
                in_string = False
        elif ch in "\"'":
            in_string = True
            quote = ch
            out.append(ch)
        elif ch == "-" and i + 1 < len(line) and line[i + 1] == "-":
            break
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def audit(path: Path, schema: dict) -> list[tuple[int, str, str, str]]:
    """Return (line, binding, property, class) for each invalid assignment."""
    problems: list[tuple[int, str, str, str]] = []
    lines = path.read_text(encoding="utf-8").split("\n")
    known = {p for p in schema["Classes"]}

    # binding name -> declared class, discovered as we walk the file.
    bindings: dict[str, str] = {}

    for index, raw in enumerate(lines):
        line = strip_comment(raw)
        if not line.strip():
            continue

        # Scope: a binding only means an Instance inside the function that created
        # it. `local card = Kit.instance("Frame", ...)` and the `card` of
        # `for _, card in self.cards do` are different things.
        if re.match(r"\s*(local\s+)?function\b", line):
            bindings.clear()
        # A name introduced as a loop variable or a plain local shadows any binding.
        for loop in re.finditer(r"\bfor\b([^\n]*?)\bin\b", line):
            for name in re.findall(r"[A-Za-z_]\w*", loop.group(1)):
                bindings.pop(name, None)
        for local in re.finditer(r"\blocal\s+([A-Za-z_]\w*)\s*=(?!=)", line):
            if not re.search(r"=\s*(?:Kit\.|Instance\.new)", line):
                bindings.pop(local.group(1), None)

        # `local x = Kit.instance("Frame"` / `self.x = Kit.panel(` / `x = Instance.new("Part"`
        for helper, fixed in CONSTRUCTORS.items():
            pattern = re.escape(helper) + r"\(\s*(?:\"([A-Za-z]+)\")?"
            for match in re.finditer(pattern, line):
                cls = match.group(1) if match.group(1) and helper in ("Kit.instance", "Instance.new") else fixed
                if not cls or cls not in known:
                    continue
                prefix = line[: match.start()]
                # Find the assignment target immediately before the call.
                target = re.search(r"([A-Za-z_][\w\.]*)\s*=\s*$", prefix)
                if target:
                    bindings[target.group(1)] = cls
                # A `return Kit.button(...)` or bare call has no binding.

        # `local b = Kit.button(` -> TextButton
        if re.search(r"=\s*Kit\.button\(", line):
            target = re.search(r"([A-Za-z_][\w\.]*)\s*=\s*Kit\.button\(", line)
            if target:
                bindings[target.group(1)] = "TextButton"

        # Now check this line's assignments against any known binding.
        for name, cls in bindings.items():
            for match in re.finditer(re.escape(name) + r"\.([A-Za-z_]\w*)\s*=(?!=)", line):
                prop = match.group(1)
                # A binding is dropped when the name is reassigned to something else.
                if prop in class_members(schema, cls):
                    continue
                problems.append((index + 1, name, prop, cls))

        # Reassignment to a non-instance clears the binding.
        for name in list(bindings):
            if re.search(r"\b" + re.escape(name) + r"\s*=\s*(?!.*(?:Kit\.|Instance\.new))", line) and not re.search(
                re.escape(name) + r"\s*=\s*(?:Kit\.|Instance\.new)", line
            ):
                # Only clear when the name is being (re)assigned on this line.
                if re.search(r"(?:local\s+)?" + re.escape(name) + r"\s*=", line):
                    bindings.pop(name, None)

    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    files = sorted(ROOT.glob("src/**/*.luau"))
    total = 0
    for path in files:
        for line, name, prop, cls in audit(path, schema):
            total += 1
            rel = path.relative_to(ROOT).as_posix()
            print(f"FAIL {rel}:{line}: {name}.{prop} is not a valid member of {cls}")
    if total:
        print(f"\n{total} invalid instance property assignment(s) found.")
        print("Roblox raises '<name> is not a valid member of <Class>' at runtime for each.")
        return 1
    if not args.quiet:
        print(f"Property audit clean: {len(files)} source files, no invalid instance properties.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
