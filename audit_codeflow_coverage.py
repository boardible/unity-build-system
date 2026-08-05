#!/usr/bin/env python3
"""
Audits a CodeFlow-migrated game for FunctionHeaderNode functions in the original
FlowGraph subflow assets that have no corresponding ported C# method.

Root cause this guards against: a subflow .asset file can serialize MORE THAN ONE
FunctionHeaderNode (Charades-style, one file per subflow with several functions inside)
or a game can register more subflow files than actually got read end-to-end during
decode. Either way, a function can be silently dropped from the port while everything
else still compiles and passes smoke (smoke only proves RPCs/data flow mechanically,
not that real gameplay content/logic exists behind it) — this is exactly how Charades'
FilterDeck (word-deck population) and QDC's SelectTargetAnswer went undetected.

Usage:
    python3 Scripts/audit_codeflow_coverage.py <GameName>
    python3 Scripts/audit_codeflow_coverage.py --all

For each subflow asset found under Assets/App/Games/<Game>/Gameplay/ (both the flat
Charades-style layout and the graphs/ per-node-split layout), lists every
FunctionHeaderNode name and reports whether a same-named (whitespace/quote-insensitive)
method exists anywhere in that game's Gameplay/*.cs files. Functions with an empty node
set (baseBlocks: [] and no locally-defined FunctionHeaderNode) are reported separately
as "orphaned" (already-dead per existing project convention) rather than "missing" —
still shown so a human can sanity-check that judgment, never silently dropped.
"""
import argparse
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_flow import load_flow_nodes  # noqa: E402

GAMES_ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Assets", "App", "Games")


def normalize(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())


def find_subflow_assets(gameplay_dir: str) -> list:
    """Every *Flow_*.asset under the game's Gameplay root, flat or under graphs/."""
    patterns = [
        os.path.join(gameplay_dir, "*Flow_*.asset"),
        os.path.join(gameplay_dir, "graphs", "*Flow_*.asset"),
    ]
    found = []
    for pat in patterns:
        found.extend(glob.glob(pat))
    return sorted(set(found))


def ported_method_names(gameplay_dir: str) -> set:
    """Every private/protected/public method name declared directly in this game's
    Gameplay/*.cs files (top-level only, not Widgets/Prefabs/Motion subfolders — those
    are presenter/view code, not CodeFlow port targets)."""
    names = set()
    pattern = re.compile(
        r"\b(?:private|protected|public|internal)\s+(?:static\s+)?(?:async\s+)?"
        r"(?:UniTask(?:<[^>]*>)?|UniTaskVoid|void|bool|int|string|float)\s+"
        r"([A-Za-z_][A-Za-z0-9_]*)\s*\("
    )
    for cs_path in glob.glob(os.path.join(gameplay_dir, "*.cs")):
        with open(cs_path, encoding="utf-8") as f:
            content = f.read()
        for m in pattern.finditer(content):
            names.add(m.group(1))
    return names


def ported_cs_source(gameplay_dir: str) -> str:
    """Concatenated source of every top-level Gameplay/*.cs file, for substring checks."""
    chunks = []
    for cs_path in glob.glob(os.path.join(gameplay_dir, "*.cs")):
        with open(cs_path, encoding="utf-8") as f:
            chunks.append(f.read())
    return "\n".join(chunks)


FIELD_WRITER_CLASSES = {"SetDataNode", "SetContextNode", "SetListNode"}


def reachable_fields(nodes: dict, start_fid: str) -> set:
    """BFS over every outgoing port connection from start_fid, collecting the 'field'
    attribute of any SetDataNode/SetContextNode/SetListNode reached — an approximation
    of "what DataRepo keys does this function's body observably write to." Doesn't
    attempt to isolate one function from a sibling function in the same file (their
    subgraphs are disconnected in practice, so plain reachability is enough), and
    doesn't follow into called subflows (cross-file FunctionCallerNode targets) —
    fields written by a CALLED function are that function's own responsibility to audit."""
    seen = set()
    stack = [start_fid]
    fields = set()
    while stack:
        fid = stack.pop()
        if fid in seen or fid not in nodes:
            continue
        seen.add(fid)
        node = nodes[fid]
        if node["class"] in FIELD_WRITER_CLASSES:
            field = node["fields"].get("field")
            if field:
                fields.add(field.strip())
        for target_ids in node["outgoing"].values():
            for tid in target_ids:
                if tid not in seen:
                    stack.append(tid)
    return fields


WRITE_CALL_PATTERN = re.compile(
    r"\b(?:Set|SetForPlayer|SetList|SetForTeam)\s*(?:<[^>]*>)?\s*\(\s*([A-Za-z_][A-Za-z0-9_.]*|\"[^\"]*\")"
)
CONST_DECL_PATTERN = re.compile(
    r'\bconst\s+string\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]*)"'
)


def written_field_literals(cs_source: str) -> set:
    """Every field name actually passed as the first argument to a Set-family call,
    resolving `private const string kX = "Y";` constants back to their literal value
    first. This is the real "does this data key get WRITTEN anywhere" signal — a bare
    string-literal search over-matches on reads/comments (this is exactly what produced
    a false-negative on Charades' TurnType, which is read via GetForPlayer but never
    written anywhere — a real, confirmed gap the looser check incorrectly cleared)."""
    const_map = {name: value for name, value in CONST_DECL_PATTERN.findall(cs_source)}
    written = set()
    for m in WRITE_CALL_PATTERN.finditer(cs_source):
        arg = m.group(1)
        if arg.startswith('"'):
            written.add(arg.strip('"'))
        elif arg in const_map:
            written.add(const_map[arg])
    return written


def fields_covered(fields: set, written: set) -> bool:
    """True if EVERY field this function writes is itself written somewhere in the
    ported C# (via an actual Set-family call) — a rename-proof signal that doesn't
    over-match on reads, comments, or unrelated string literals."""
    if not fields:
        return False  # no observable writes at all — can't use this signal either way
    return all(f in written for f in fields)


def audit_game(game: str) -> int:
    gameplay_dir = os.path.join(GAMES_ROOT, game, "Gameplay")
    if not os.path.isdir(gameplay_dir):
        print(f"[{game}] no Gameplay directory found, skipping")
        return 0

    assets = find_subflow_assets(gameplay_dir)
    if not assets:
        print(f"[{game}] no subflow assets found (pure SimpleStandaloneFlow, or not CodeFlow at all?)")
        return 0

    ported = ported_method_names(gameplay_dir)
    ported_norm = {normalize(n): n for n in ported}
    cs_source = ported_cs_source(gameplay_dir)
    written = written_field_literals(cs_source)

    missing = []
    renamed = []
    orphaned = []
    ok = []

    for asset_path in assets:
        try:
            nodes = load_flow_nodes(asset_path)
        except Exception as e:  # noqa: BLE001
            print(f"[{game}] FAILED to parse {os.path.basename(asset_path)}: {e}")
            continue

        headers = [(fid, n) for fid, n in nodes.items() if n["class"] == "FunctionHeaderNode"]
        rel = os.path.relpath(asset_path, gameplay_dir)

        if not headers:
            orphaned.append((rel, None))
            continue

        for fid, n in headers:
            fn_name = (n.get("name") or "").strip()
            if not fn_name:
                orphaned.append((rel, "(unnamed)"))
                continue
            key = normalize(fn_name)
            if key in ported_norm:
                ok.append((rel, fn_name, ported_norm[key]))
                continue

            fields = reachable_fields(nodes, fid)
            if fields_covered(fields, written):
                renamed.append((rel, fn_name, sorted(fields)))
            else:
                missing.append((rel, fn_name, sorted(fields)))

    print(f"\n=== {game} ===")
    print(f"  {len(ok)} exact-name match, {len(renamed)} renamed-but-field-covered (likely fine), "
          f"{len(orphaned)} orphaned (empty), {len(missing)} MISSING (name AND fields both unmatched)")
    if missing:
        for rel, fn_name, fields in missing:
            field_note = f" [writes: {', '.join(fields)}]" if fields else " [no observable field writes found]"
            print(f"  [MISSING] {rel}: FUNCTION \"{fn_name}\" has no matching C# method{field_note}")
    if renamed:
        for rel, fn_name, fields in renamed:
            print(f"  [renamed?] {rel}: FUNCTION \"{fn_name}\" not name-matched, but all its fields "
                  f"({', '.join(fields)}) are written somewhere in the C# port — verify manually, likely just renamed")
    if orphaned:
        for rel, tag in orphaned:
            label = tag or "no FunctionHeaderNode (empty baseBlocks)"
            print(f"  [orphaned?] {rel}: {label}")

    return len(missing)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", nargs="?", help="Game folder name under Assets/App/Games/")
    parser.add_argument("--all", action="store_true", help="Audit every game with a Gameplay/ folder")
    args = parser.parse_args()

    if args.all:
        games = sorted(
            d for d in os.listdir(GAMES_ROOT)
            if os.path.isdir(os.path.join(GAMES_ROOT, d, "Gameplay"))
        )
    elif args.game:
        games = [args.game]
    else:
        parser.print_help()
        sys.exit(1)

    total_missing = 0
    for game in games:
        total_missing += audit_game(game)

    print(f"\n=== TOTAL: {total_missing} missing function(s) across {len(games)} game(s) ===")
    sys.exit(1 if total_missing > 0 else 0)


if __name__ == "__main__":
    main()
