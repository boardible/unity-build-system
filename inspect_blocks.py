#!/usr/bin/env python3
"""List every engine block for a game: title, class, and file path.

Restores the block-discovery tool referenced by .github/copilot-instructions.md's
CodeFlow Migration section (missing from the repo). Usage:

    python3 Scripts/inspect_blocks.py <Game>
    python3 Scripts/inspect_blocks.py <Game> --resolve    # also print a ResolveBlocks() scaffold
    python3 Scripts/inspect_blocks.py <Game> --subflows   # also scan blocks referenced only by subflow PACs

Run from the repo root (e.g. boardgames/).
"""
import argparse
import os
import re
import sys

ASSETS_ROOT = "Assets"


def _build_script_class_index(root_dirs):
    """guid -> class name, scanned from every *.cs.meta under root_dirs."""
    index = {}
    for root_dir in root_dirs:
        for dirpath, _dirnames, filenames in os.walk(root_dir):
            for fn in filenames:
                if not fn.endswith(".cs.meta"):
                    continue
                meta_path = os.path.join(dirpath, fn)
                cs_path = meta_path[: -len(".meta")]
                if not os.path.isfile(cs_path):
                    continue
                try:
                    with open(meta_path, encoding="utf-8") as f:
                        m = re.search(r"^guid:\s*([0-9a-f]+)", f.read(), re.MULTILINE)
                except OSError:
                    continue
                if not m:
                    continue
                class_name = os.path.splitext(fn[: -len(".meta")])[0]
                index[m.group(1)] = class_name
    return index


def _find_gameplay_root(game):
    candidates = [
        os.path.join(ASSETS_ROOT, "App", "Games", game, "Gameplay"),
    ]
    for c in candidates:
        if os.path.isdir(c):
            return c
    raise SystemExit(f"ERROR: could not find Gameplay folder for game '{game}' under {candidates}")


def _block_info(asset_path, class_index):
    try:
        with open(asset_path, encoding="utf-8", errors="replace") as f:
            content = f.read(4000)
    except OSError:
        return None
    title_m = re.search(r"^  title:\s*(.*)$", content, re.MULTILINE)
    name_m = re.search(r"^  m_Name:\s*(.*)$", content, re.MULTILINE)
    script_m = re.search(r"^  m_Script:\s*\{fileID:\s*\d+,\s*guid:\s*([0-9a-f]+)", content, re.MULTILINE)
    title = (title_m.group(1).strip() if title_m else "") or (name_m.group(1).strip() if name_m else "")
    class_name = class_index.get(script_m.group(1), "?") if script_m else "?"
    return title, class_name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", help="Game folder name under Assets/App/Games/")
    parser.add_argument("--resolve", action="store_true", help="Print a ResolveBlocks() scaffold")
    parser.add_argument("--subflows", action="store_true", help="Also include blocks/ and graphs/ subfolders (PAC-only refs)")
    args = parser.parse_args()

    gameplay_root = _find_gameplay_root(args.game)
    class_index = _build_script_class_index([os.path.join(ASSETS_ROOT, "GameBox")])

    scan_dirs = [os.path.join(gameplay_root, "engine", "blocks")]
    if args.subflows:
        for extra in ("blocks", "graphs"):
            p = os.path.join(gameplay_root, extra)
            if os.path.isdir(p):
                scan_dirs.append(p)

    rows = []
    seen_paths = set()
    for scan_dir in scan_dirs:
        if not os.path.isdir(scan_dir):
            continue
        for dirpath, _dirnames, filenames in os.walk(scan_dir):
            for fn in sorted(filenames):
                if not fn.endswith(".asset"):
                    continue
                asset_path = os.path.join(dirpath, fn)
                if asset_path in seen_paths:
                    continue
                seen_paths.add(asset_path)
                info = _block_info(asset_path, class_index)
                if info is None:
                    continue
                title, class_name = info
                rows.append((title or os.path.splitext(fn)[0], class_name, asset_path))

    rows.sort(key=lambda r: (r[1], r[0]))
    for title, class_name, path in rows:
        print(f"{class_name:24} {title:40} {path}")
    print(f"\n=== {len(rows)} blocks ===", file=sys.stderr)

    if args.resolve:
        print("\n--- ResolveBlocks() scaffold ---\n")
        type_to_field_prefix = {
            "ListPoolBlock": "ListPoolBlock",
            "WidgetBlock": "WidgetBlock",
            "MissionBlock": "MissionBlock",
            "ScoreBlock": "ScoreBlock",
            "FullScreenBlock": "FullScreenBlock",
            "BannerBlock": "BannerBlock",
            "ContainerBlock": "ContainerBlock",
        }
        for title, class_name, _path in rows:
            if class_name not in type_to_field_prefix or not title or title.startswith(class_name):
                continue
            field = "_" + title[0].lower() + title[1:].replace(" ", "").replace("#", "")
            print(f'        BindBlock(ref {field}, {args.game}FlowApi.Blocks.{title.replace(" ", "").replace("#", "")});')


if __name__ == "__main__":
    main()
