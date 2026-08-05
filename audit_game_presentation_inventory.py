#!/usr/bin/env python3
"""Per-game inventory of authored presentation, and whether the flow drives it.

`audit_presentation_wiring.py` asks "did the C# drop a call the graph made?", which
only works while the legacy graph survives. This one asks the question that keeps
biting instead: **this game has its own prefabs, widgets and animation blocks — is
each of them actually driven by anything?** That is how Sushi Go shipped with a
conveyor belt nobody started and a draft-summary popup nobody showed.

Three detectors, run per game:

  flow-field    An engine block declares a prefabField with `valueComeFromFlow: 1`
                — the presenter expects the flow to feed that value at runtime —
                and the label never appears in the game's C# flow. This is the
                strongest signal in the file: the widget renders its default
                forever. (Sushi Go's SushiGO_Fullscreen_Round.currentRound and the
                banner's playerName/playerSprite were exactly this shape.)

  unplayed-anim An animation-ish block (Banner/FullScreen/Reaction/Score/Mission)
                exists in the engine but its title never appears in the C# flow.
                Those blocks do nothing until something explicitly plays them.

  orphan-prefab A prefab living in the game's own folder that carries a game-owned
                presenter script and is referenced by no asset at all — authored
                content wired to nothing.

Every hit is a lead, not a verdict: a block can legitimately be driven purely by
authored template data. Read the hit before acting on it.

Usage:
    python3 Scripts/audit_game_presentation_inventory.py [Game ...]
    python3 Scripts/audit_game_presentation_inventory.py --detector flow-field
"""

from __future__ import annotations

import argparse
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAMES_ROOT = os.path.join(REPO, "Assets", "App", "Games")
SCAN_ROOTS = [os.path.join(REPO, "Assets", "App"), os.path.join(REPO, "Assets", "GameBox")]

ANIMATION_BLOCK_TYPES = {
    "BannerBlock", "FullScreenBlock", "ReactionBlock", "ScoreBlock",
    "MissionBlock", "VFXBlock", "AnimationBlock",
}

# Fed by the block/presenter plumbing itself, not by flow code.
IGNORED_FLOW_LABELS = {
    "PlayerId", "TeamId", "OwnerId", "Aspect", "TooltipOverride", "hiddenFieldOverride",
}

SCRIPT_GUID_RE = re.compile(r"m_Script: \{fileID: 11500000, guid: ([a-f0-9]{32})")
TITLE_RE = re.compile(r"^  title: (.*)$", re.M)
PREFAB_FIELD_RE = re.compile(
    r"- selectedContext:.*?label: (\w+).*?valueComeFromFlow: (\d)",
    re.S,
)


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


def build_script_guid_map():
    """script guid -> class name, from every .cs.meta in the project."""
    mapping = {}
    for root in SCAN_ROOTS:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in ("Library", "Temp", "obj")]
            for name in filenames:
                if not name.endswith(".cs.meta"):
                    continue
                text = read(os.path.join(dirpath, name))
                match = re.search(r"guid: ([a-f0-9]{32})", text)
                if match:
                    mapping[match.group(1)] = name[: -len(".cs.meta")]
    return mapping


def game_ids():
    return sorted(
        name for name in os.listdir(GAMES_ROOT)
        if os.path.isdir(os.path.join(GAMES_ROOT, name))
    )


def flow_sources(game):
    """Concatenated C# owned by this game (its flow and helpers)."""
    parts = []
    for path in iter_files([os.path.join(GAMES_ROOT, game)], (".cs",)):
        parts.append(read(path))
    return "\n".join(parts)


def mentions(blob, token):
    return re.search(r"(?<![\w])" + re.escape(token) + r"(?![\w])", blob) is not None


def game_block_assets(game, guid_map):
    """[(path, class name, title, raw text)] for every block asset owned by the game."""
    results = []
    for path in iter_files([os.path.join(GAMES_ROOT, game)], (".asset",)):
        text = read(path)
        guids = SCRIPT_GUID_RE.findall(text)
        if not guids:
            continue
        klass = guid_map.get(guids[0], "?")
        if not klass.endswith("Block"):
            continue
        title_match = TITLE_RE.search(text)
        title = title_match.group(1).strip() if title_match else ""
        results.append((path, klass, title, text))
    return results


def build_asset_reference_index():
    """guid -> True when any serialized asset references it."""
    referenced = set()
    for path in iter_files(SCAN_ROOTS, (".asset", ".prefab", ".unity", ".controller")):
        for guid in re.findall(r"guid: ([a-f0-9]{32})", read(path)):
            referenced.add(guid)
    return referenced


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("games", nargs="*")
    parser.add_argument("--detector", choices=["flow-field", "unplayed-anim", "orphan-prefab", "all"], default="all")
    args = parser.parse_args()

    guid_map = build_script_guid_map()
    targets = args.games or game_ids()
    referenced = build_asset_reference_index() if args.detector in ("orphan-prefab", "all") else set()

    total = 0
    for game in targets:
        if not os.path.isdir(os.path.join(GAMES_ROOT, game)):
            print(f"!! unknown game '{game}'", file=sys.stderr)
            continue

        blob = flow_sources(game)
        findings = []
        blocks = game_block_assets(game, guid_map)

        for path, klass, title, text in blocks:
            rel = os.path.relpath(path, REPO)

            if args.detector in ("flow-field", "all"):
                for label, from_flow in PREFAB_FIELD_RE.findall(text):
                    if from_flow != "1" or label in IGNORED_FLOW_LABELS:
                        continue
                    if mentions(blob, label):
                        continue
                    findings.append(
                        f"  [FLOW-FIELD]    {klass} '{title}' expects flow to supply '{label}' — "
                        f"never set in C# ({os.path.basename(rel)})")

            if args.detector in ("unplayed-anim", "all"):
                if klass in ANIMATION_BLOCK_TYPES and title and not mentions(blob, title):
                    findings.append(
                        f"  [UNPLAYED-ANIM] {klass} '{title}' is never referenced by the C# flow "
                        f"({os.path.basename(rel)})")

        if args.detector in ("orphan-prefab", "all"):
            game_dir = os.path.join(GAMES_ROOT, game)
            for path in iter_files([game_dir], (".prefab",)):
                meta = read(path + ".meta")
                guid_match = re.search(r"guid: ([a-f0-9]{32})", meta)
                if not guid_match:
                    continue
                guid = guid_match.group(1)
                text = read(path)
                scripts = {guid_map.get(g, "") for g in SCRIPT_GUID_RE.findall(text)}
                owns_game_script = any(
                    s and os.path.exists(os.path.join(game_dir, ""))
                    and any(s == os.path.splitext(os.path.basename(p))[0]
                            for p in iter_files([game_dir], (".cs",)))
                    for s in scripts
                )
                if not owns_game_script:
                    continue
                # `referenced` counts this prefab's own meta guid appearing elsewhere.
                hits = sum(1 for _ in [1] if guid in referenced)
                if not hits:
                    findings.append(
                        f"  [ORPHAN-PREFAB] {os.path.relpath(path, REPO)} carries a game script but "
                        f"no asset references it")

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
