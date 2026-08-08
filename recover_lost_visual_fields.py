#!/usr/bin/env python3
"""Walk git history looking for a value a visual field used to have.

A DataReference_Constant that is empty today may have been filled before - migrations in this repo
have dropped serialized data more than once. A filled Sprite constant keeps both identifiers:

    valueByte:  0001...  (the guid, hex-encoded ASCII)
    _readableValue: 1f6e1e43faa22408d968769377a1aea0      <- sprite guid
    overrideDescription: BG_bamboo_0 (UnityEngine.Sprite) <- sprite name

so recovering one from history gives back the exact asset, not a guess.

Usage:
  python3 Scripts/recover_lost_visual_fields.py <Game> [label]     # default label: image
"""

import importlib.util
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

spec = importlib.util.spec_from_file_location("audit", os.path.join(HERE, "audit_prefab_visual_fields.py"))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

MAX_REVS = 60


def git(*args):
    return subprocess.run(
        ["git", "-C", ROOT, *args], capture_output=True, text=True, errors="ignore"
    ).stdout


def value_of(text, label):
    """(has_value, description, guid) for `label`'s constant in this revision of the asset."""
    refids = audit.parse_refids(text)
    for e in audit.parse_prefab_fields(text):
        if e["label"] != label or e["context"] != "Constant":
            continue
        cls, data = refids.get(e["rid"], (None, ""))
        if cls != "DataReference_Constant":
            continue
        if audit.constant_is_empty(data):
            return (False, None, None)
        desc = re.search(r"^[ \t]*overrideDescription:[ \t]*(.*)$", data, re.M)
        guid = re.search(r"^[ \t]*_readableValue:[ \t]*(.*)$", data, re.M)
        guid_value = guid.group(1).strip() if guid else ""
        if not guid_value:
            # Older revisions predate _readableValue; the guid is still in valueByte, which stores it
            # as hex-encoded ASCII. Pull the 32 hex chars back out rather than giving up on it.
            vb = re.search(r"^[ \t]*valueByte:[ \t]*(\S+)$", data, re.M)
            if vb:
                try:
                    raw = bytes.fromhex(vb.group(1)).decode("ascii", "ignore")
                    hit = re.search(r"[0-9a-f]{32}", raw)
                    guid_value = hit.group(0) if hit else ""
                except ValueError:
                    guid_value = ""
        return (True, desc.group(1).strip() if desc else "?", guid_value or "?")
    return (False, None, None)


def main():
    if not sys.argv[1:]:
        print(__doc__)
        return 1
    game = sys.argv[1]
    label = sys.argv[2] if len(sys.argv) > 2 else "image"

    # Re-derive the findings in process rather than scraping the text report: the report pads columns
    # and a long block title runs into the next one, which silently produced names like
    # "SkipButtonQuestionWidgetBlock" that match no file on disk.
    guid_map = audit.build_guid_map()
    game_dir = os.path.join(ROOT, "Assets", "App", "Games", game)
    paths = {}
    for asset in audit.walk_files(game_dir, ".asset"):
        try:
            with open(asset, "r", errors="ignore") as fh:
                text = fh.read()
        except OSError:
            continue
        if "prefabFields" not in text:
            continue
        refids = audit.parse_refids(text)
        template = audit.template_field_names(text, refids)
        pguid, _proot = audit.prefab_guid_of_block(text)
        prefab_path = guid_map.get(pguid) if pguid else None
        if not prefab_path or "no_image" not in audit.prefab_default_sprites(prefab_path, guid_map):
            continue
        for e in audit.parse_prefab_fields(text):
            if e["label"] != label or e["context"] != "Constant" or e["from_flow"]:
                continue
            if e["label"] in template:
                continue
            cls, data = refids.get(e["rid"], (None, ""))
            if cls == "DataReference_Constant" and audit.constant_is_empty(data):
                paths[os.path.relpath(asset, ROOT)] = audit.block_title(text, asset)

    if not paths:
        print(f"{game}: nenhum bloco com '{label}' vazio sobre um prefab que cai em no_image")
        return 0

    print(f"{game}: {len(paths)} blocos\n")
    recovered, never = [], []
    for path in sorted(paths):
        block = paths[path]
        revs = git("log", "--format=%H", "--follow", "--", path).split()
        hit = None
        for rev in revs[:MAX_REVS]:
            text = git("show", f"{rev}:{path}")
            if not text:
                continue
            has, desc, guid = value_of(text, label)
            if has:
                hit = (rev[:10], desc, guid)
                break
        if hit:
            recovered.append((block, *hit))
        else:
            never.append((block, f"{len(revs)} revisões, sempre vazio"))

    if recovered:
        print(f"RECUPERÁVEL ({len(recovered)}):")
        for block, rev, desc, guid in recovered:
            print(f"  {block:<20} {rev}  {desc}   guid={guid}")
    if never:
        print(f"\nNUNCA TEVE VALOR ({len(never)}):")
        for block, why in never:
            print(f"  {block:<20} {why}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
