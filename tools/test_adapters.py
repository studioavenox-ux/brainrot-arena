#!/usr/bin/env python3
"""Execute real Roblox adapters in Luau against explicit engine-boundary test doubles."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
from build_place import lua

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", default=shutil.which("luau") or str(ROOT / ".tools/luau-0.744/luau"))
    args = parser.parse_args()
    output = ROOT / ".tools/adapter-run.luau"
    output.parent.mkdir(exist_ok=True)
    schema = json.loads((ROOT / "tests/fixtures/roblox-api.json").read_text())
    lines = ['--!nocheck', 'local Mock = require("../tests/roblox_mock")', 'local sources = {}']
    for path in sorted((ROOT / "src").rglob("*.luau")):
        source = path.read_text(encoding="utf-8")
        assert "]====]" not in source
        lines.append(f'sources[{json.dumps(path.relative_to(ROOT).as_posix())}] = [====[{source}]====]')
    lines.append("local schema = " + lua(schema))
    lines.append('require("../tests/adapters.spec")(Mock, sources, schema)')
    output.write_text("\n".join(lines), encoding="utf-8")
    result = subprocess.run([args.luau, str(output)], cwd=ROOT)
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
