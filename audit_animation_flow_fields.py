#!/usr/bin/env python3
"""Find [AnimationField(FromFlow)] fields that no CodeFlow ever supplies.

A `FromFlow` animation field is fed *only* through `block.flowValues["<fieldName>"]`.
In the YAML era `AnimationsUtils.InjectParameters` filled that dictionary from the
ShowAnimation node's input ports; a CodeFlow has no node, so the C# has to write
`flowValues` itself. Miss it and the field silently keeps the prefab's serialized
default: empty string, null sprite, zero. The animation plays, blank.

Usage:
    python3 Scripts/audit_animation_flow_fields.py              # every game
    python3 Scripts/audit_animation_flow_fields.py Quartz Dobro  # only these
    python3 Scripts/audit_animation_flow_fields.py --json
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

GAMES_ROOT = Path(__file__).resolve().parent.parent / "Assets" / "App" / "Games"

# [AnimationField(AnimationFieldSource.FromFlow)] / [AnimationField(FromFlow)], then
# (optionally after more attributes) the field declaration whose name we want.
ATTR_RE = re.compile(r"\[\s*AnimationField\s*\(([^)]*)\)\s*\]")
FIELD_RE = re.compile(
    r"^\s*(?:\[[^\]]*\]\s*)*"                      # any further attributes
    r"(?:public|private|protected|internal)\s+"
    r"(?:static\s+|readonly\s+)*"
    r"([\w<>\[\],.?]+)\s+"                          # type
    r"(\w+)\s*(?:=|;|\{)"                           # name
)


def game_dirs(selected: list[str]) -> list[Path]:
    dirs = sorted(d for d in GAMES_ROOT.iterdir() if d.is_dir())
    if not selected:
        return dirs
    wanted = {s.lower() for s in selected}
    return [d for d in dirs if d.name.lower() in wanted]


def scan_game(game_dir: Path) -> dict:
    sources = sorted(game_dir.rglob("*.cs"))
    corpus = "\n".join(p.read_text(encoding="utf-8", errors="replace") for p in sources)
    # Two shapes both mean "fed": a direct index write and a collection initializer.
    #   block.flowValues["fieldName"] = value;
    #   block.flowValues = new Dictionary<string, object> { ["fieldName"] = value };
    supplied = set(re.findall(r'flowValues\s*\[\s*"([^"]+)"\s*\]', corpus))
    supplied |= set(re.findall(r'\[\s*"([A-Za-z_]\w*)"\s*\]\s*=', corpus))
    # Weakest signal: the name quoted anywhere at all (a helper may route it through a
    # variable or a const). Reported separately — it is a hint, not proof.
    quoted = set(re.findall(r'"([A-Za-z_]\w*)"', corpus))

    presenters: dict[str, dict] = {}
    for path in sources:
        text = path.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()
        cls = None
        for i, line in enumerate(lines):
            m = re.search(r"\bclass\s+(\w+)", line)
            if m:
                cls = m.group(1)
            # A commented-out field is not a contract: BDB_ResultsAnimation keeps four of them.
            if line.lstrip().startswith("//"):
                continue
            a = ATTR_RE.search(line)
            if not a or "FromFlow" not in a.group(1):
                continue
            # the field declaration is on this line after the attribute, or below it
            tail = line[a.end():]
            decl = FIELD_RE.match(tail) if tail.strip() else None
            j = i
            while decl is None and j + 1 < len(lines) and j - i < 6:
                j += 1
                decl = FIELD_RE.match(lines[j])
            if decl is None:
                continue
            ftype, fname = decl.group(1), decl.group(2)
            entry = presenters.setdefault(
                cls or path.stem,
                {"file": str(path.relative_to(game_dir.parent.parent.parent.parent)), "fields": []},
            )
            entry["fields"].append(
                {
                    "name": fname,
                    "type": ftype,
                    "supplied": fname in supplied,
                    "quoted_only": fname not in supplied and fname in quoted,
                }
            )
    return presenters


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    as_json = "--json" in sys.argv

    report = {}
    for d in game_dirs(args):
        presenters = scan_game(d)
        # A field whose name is quoted somewhere in the game but not in a flowValues index is
        # reported separately, not as a gap: HanabiFlow writes
        # `flowValues[fields[i]] = ...` over a string array, which no literal-index scan can see.
        blank = {
            cls: info
            for cls, info in presenters.items()
            if any(not f["supplied"] and not f["quoted_only"] for f in info["fields"])
        }
        if blank:
            report[d.name] = blank

    if as_json:
        print(json.dumps(report, indent=2))
        return 0

    total_missing = 0
    for game, presenters in sorted(report.items()):
        print(f"\n=== {game} ===")
        for cls, info in sorted(presenters.items()):
            missing = [f for f in info["fields"] if not f["supplied"] and not f["quoted_only"]]
            if not missing:
                continue
            total_missing += len(missing)
            marks = ", ".join(
                f"{f['name']}:{f['type']}" + (" (quoted elsewhere)" if f["quoted_only"] else "")
                for f in missing
            )
            print(f"  {cls}  {len(missing)}/{len(info['fields'])} unsupplied")
            print(f"      {marks}")
    print(f"\n{total_missing} unsupplied FromFlow fields across {len(report)} games")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
