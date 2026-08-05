#!/usr/bin/env python3
"""Find authored presentation that nothing ever triggers.

This is the companion to `audit_codeflow_coverage.py`, which only sees
`FunctionHeaderNode`s and the DataRepo fields they write. The bug class it is
blind to — and the one that made Sushi Go ship without its conveyor belt, its
draft-summary popup and its collection art — is a `[VisualAction]` on a
presenter that the original FlowBox graph invoked via `InvokeActionNode` and the
typed CodeFlow port simply never called. Those invocations have zero DataRepo
footprint, so every existing gate stays green while the animation is gone.

Two detectors:

  dead-action   A [VisualAction] declared on a game's own presenter/widget that
                no C# code calls and no serialized asset names. The authored
                animation exists in the prefab and nothing can ever fire it.

  unported      An InvokeActionNode still present in a legacy flow graph whose
                target method is not called anywhere in that game's C# flow.
                Only meaningful for games whose legacy `.asset` graphs survive.

Both are triage signals, not verdicts: read the hit before acting on it.

Usage:
    python3 Scripts/audit_presentation_wiring.py                # every game
    python3 Scripts/audit_presentation_wiring.py SushiGo Quartz # some games
    python3 Scripts/audit_presentation_wiring.py --detector dead-action
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections import defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAMES_ROOT = os.path.join(REPO, "Assets", "App", "Games")
CODE_ROOTS = [
    os.path.join(REPO, "Assets", "App"),
    os.path.join(REPO, "Assets", "GameBox"),
    os.path.join(REPO, "Assets", "Commons", "Runtime"),
]
ASSET_ROOTS = [os.path.join(REPO, "Assets", "App")]
ASSET_EXTENSIONS = (".asset", ".prefab", ".anim", ".unity", ".controller")

# Declared on framework base classes, wired generically by block/prefab data.
# Flagging these produces pure noise.
FRAMEWORK_ACTIONS = {
    "Show", "Hide", "ShowPool", "HidePool", "HideAfterSeconds", "HideForSeconds",
    "SetPresenterState", "CallTooltip", "CallTooltipWithText", "SetTooltipOverride",
    "SetText", "Op",
}

VISUAL_ACTION_RE = re.compile(r"\[\s*VisualAction\s*\]")
METHOD_DECL_RE = re.compile(
    r"^\s*(?:\[[^\]]*\]\s*)*"
    r"(?:public|private|protected|internal)\s+"
    r"(?:(?:static|virtual|override|async|sealed|new|partial)\s+)*"
    r"[\w<>\[\],\.\s]+?\s+"
    r"(\w+)\s*\("
)
INVOKE_ACTION_NAME_RE = re.compile(r"^\s{2}actionName:\s*(\S+)\s*$")
TYPESTRING_RE = re.compile(r"typeString:\s*([\w\.]+)\s*,")


def iter_files(roots, extensions):
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in ("Library", "Temp", "obj")]
            for name in filenames:
                if name.endswith(extensions):
                    yield os.path.join(dirpath, name)


def read(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as handle:
            return handle.read()
    except OSError:
        return ""


def game_ids():
    return sorted(
        name for name in os.listdir(GAMES_ROOT)
        if os.path.isdir(os.path.join(GAMES_ROOT, name))
    )


def collect_visual_actions(game):
    """[(method, class, relative path)] declared under this game's folder."""
    found = []
    game_dir = os.path.join(GAMES_ROOT, game)
    for path in iter_files([game_dir], (".cs",)):
        text = read(path)
        if "VisualAction" not in text:
            continue
        lines = text.splitlines()
        current_class = "?"
        for index, line in enumerate(lines):
            class_match = re.match(r"\s*(?:public|internal|abstract|sealed|partial|\s)*class\s+(\w+)", line)
            if class_match:
                current_class = class_match.group(1)
            if not VISUAL_ACTION_RE.search(line):
                continue
            # The attribute may sit on its own line or inline before the signature.
            for offset in range(0, 4):
                if index + offset >= len(lines):
                    break
                decl = METHOD_DECL_RE.match(lines[index + offset])
                if decl:
                    found.append((decl.group(1), current_class, os.path.relpath(path, REPO)))
                    break
    return found


def build_reference_index():
    """method name -> set of files that mention it, from code and serialized data."""
    code_text = {}
    for path in iter_files(CODE_ROOTS, (".cs",)):
        code_text[path] = read(path)

    asset_text = {}
    for path in iter_files(ASSET_ROOTS, ASSET_EXTENSIONS):
        asset_text[path] = read(path)

    return code_text, asset_text


def has_caller(method, decl_path, code_text, asset_text):
    """Anything that could plausibly fire this action, outside its declaration."""
    call_re = re.compile(r"(?<![\w])(?:\.\s*" + re.escape(method) + r"\s*\(|nameof\(\s*" + re.escape(method) + r"\s*\))")
    for path, text in code_text.items():
        if method not in text:
            continue
        if os.path.relpath(path, REPO) == decl_path and len(call_re.findall(text)) == 0:
            continue
        if call_re.search(text):
            return True, os.path.relpath(path, REPO)

    # Serialized invocation: InvokeActionNode.actionName / TargetMethod.method,
    # AnimationEvent.functionName, UnityEvent m_MethodName.
    serialized_re = re.compile(
        r"(?:actionName|method|functionName|m_MethodName):\s*" + re.escape(method) + r"\s*$",
        re.MULTILINE,
    )
    for path, text in asset_text.items():
        if method not in text:
            continue
        if serialized_re.search(text):
            return True, os.path.relpath(path, REPO)
    return False, None


def collect_invoke_actions(game):
    """[(actionName, targetType, asset)] from this game's serialized flow graphs."""
    found = []
    game_dir = os.path.join(GAMES_ROOT, game)
    for path in iter_files([game_dir], (".asset",)):
        text = read(path)
        if "InvokeActionNode" not in text:
            continue
        lines = text.splitlines()
        for index, line in enumerate(lines):
            match = INVOKE_ACTION_NAME_RE.match(line)
            if not match:
                continue
            action = match.group(1)
            target = "?"
            for lookahead in range(index, min(index + 12, len(lines))):
                type_match = TYPESTRING_RE.search(lines[lookahead])
                if type_match:
                    target = type_match.group(1)
                    break
            found.append((action, target, os.path.relpath(path, REPO)))
    return found


def game_flow_sources(game):
    game_dir = os.path.join(GAMES_ROOT, game)
    return {
        os.path.relpath(path, REPO): read(path)
        for path in iter_files([game_dir], (".cs",))
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("games", nargs="*", help="Game folder names (default: all)")
    parser.add_argument("--detector", choices=["dead-action", "unported", "all"], default="all")
    parser.add_argument("--include-framework", action="store_true",
                        help="Also report generic Show/Hide/HidePool actions")
    args = parser.parse_args()

    targets = args.games or game_ids()
    code_text, asset_text = build_reference_index()

    total = 0
    for game in targets:
        if not os.path.isdir(os.path.join(GAMES_ROOT, game)):
            print(f"!! unknown game '{game}'", file=sys.stderr)
            continue

        findings = []

        if args.detector in ("dead-action", "all"):
            for method, klass, decl_path in collect_visual_actions(game):
                if method in FRAMEWORK_ACTIONS and not args.include_framework:
                    continue
                called, where = has_caller(method, decl_path, code_text, asset_text)
                if not called:
                    findings.append(f"  [DEAD-ACTION] {klass}.{method}() — no caller in code or serialized data ({decl_path})")

        if args.detector in ("unported", "all"):
            sources = game_flow_sources(game)
            flow_blob = "\n".join(
                text for path, text in sources.items()
                if path.endswith(".cs") and "/Gameplay/" in path.replace(os.sep, "/")
            )
            seen = set()
            for action, target, asset in collect_invoke_actions(game):
                if (action, target) in seen:
                    continue
                seen.add((action, target))
                if action in FRAMEWORK_ACTIONS and not args.include_framework:
                    continue
                # PieceActionNode shares the `actionName:` key with InvokeActionNode.
                # Its kSetField/kSetState/kSetTooltip verbs are the generic piece
                # field+state API, which the typed flows express as
                # SetCustomValue/SetState — not a missing presentation call.
                if target == "?" and action.startswith("k"):
                    continue
                if re.search(r"(?<![\w])" + re.escape(action) + r"(?![\w])", flow_blob):
                    continue
                findings.append(f"  [UNPORTED]    {target}.{action}() invoked by {os.path.basename(asset)} — name never appears in the C# flow")

        if findings:
            print(f"=== {game} ===")
            for line in sorted(set(findings)):
                print(line)
            print()
            total += len(set(findings))

    print(f"=== TOTAL: {total} finding(s) across {len(targets)} game(s) ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
