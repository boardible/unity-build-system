#!/usr/bin/env python3

from __future__ import annotations

import fnmatch
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PATTERN = "." + "GamesRepo"
INCLUDE_SUFFIXES = {".cs", ".py", ".sh", ".md", ".yml", ".yaml", ".json", ".txt"}
EXCLUDED_DIR_NAMES = {
    ".git",
    "Library",
    "Temp",
    "Logs",
    "obj",
    "Backups",
    "UserSettings",
    "ServerData",
    "MemoryCaptures",
}
EXCLUDED_GLOBS = {
    "**/*.meta",
    "**/*.csproj",
    "**/*.slnx",
    "**/*.dll",
    "**/*_generated.cs",
}
ALLOWED_FILES: set[str] = set()


def should_skip(path: Path) -> bool:
    rel = path.relative_to(ROOT).as_posix()
    if rel in ALLOWED_FILES:
        return True
    if any(part in EXCLUDED_DIR_NAMES for part in path.parts):
        return True
    if path.suffix not in INCLUDE_SUFFIXES:
        return True
    return any(fnmatch.fnmatch(rel, pattern) for pattern in EXCLUDED_GLOBS)


def main() -> int:
    violations: list[str] = []

    for path in ROOT.rglob("*"):
        if not path.is_file() or should_skip(path):
            continue

        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue

        for line_number, line in enumerate(text.splitlines(), start=1):
            if PATTERN not in line:
                continue

            rel = path.relative_to(ROOT).as_posix()
            violations.append(f"{rel}:{line_number}: {line.strip()}")

    if not violations:
        return 0

    print("Unexpected hidden game-root references found:")
    for violation in violations:
        print(f"  {violation}")
    if ALLOWED_FILES:
        print("Allowed transitional files:")
        for allowed in sorted(ALLOWED_FILES):
            print(f"  {allowed}")
    return 1


if __name__ == "__main__":
    sys.exit(main())