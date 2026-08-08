#!/usr/bin/env python3
"""Put back a visual-field constant using the exact payload from git history.

Companion to recover_lost_visual_fields.py. Rather than re-encoding a value (valueByte is a hex blob
whose format we would be guessing at), this copies the historical `data:` block verbatim into the
current entry for the same label, keeping today's rid. What goes back is byte-for-byte what the
designer had authored.

Dry run by default. Pass --apply to write.

Usage:
  python3 Scripts/restore_lost_visual_fields.py <Game> [label] [--apply]
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

rspec = importlib.util.spec_from_file_location("recover", os.path.join(HERE, "recover_lost_visual_fields.py"))
recover = importlib.util.module_from_spec(rspec)
rspec.loader.exec_module(recover)

MAX_REVS = 60


def rid_data_span(text, rid):
    """(start, end) of the `data:` block belonging to this rid in the RefIds section."""
    m = re.search(
        r"\n    - rid: " + re.escape(rid) + r"\n      type: \{[^}]*\}(.*?)(?=\n    - rid: |\Z)",
        text,
        re.S,
    )
    return (m.start(1), m.end(1)) if m else None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    apply = "--apply" in sys.argv
    if not args:
        print(__doc__)
        return 1
    game = args[0]
    label = args[1] if len(args) > 1 else "image"

    guid_map = audit.build_guid_map()
    game_dir = os.path.join(ROOT, "Assets", "App", "Games", game)

    done, skipped = [], []
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
        pguid, _ = audit.prefab_guid_of_block(text)
        prefab_path = guid_map.get(pguid) if pguid else None
        if not prefab_path or "no_image" not in audit.prefab_default_sprites(prefab_path, guid_map):
            continue

        entry = None
        for e in audit.parse_prefab_fields(text):
            if e["label"] == label and e["context"] == "Constant" and not e["from_flow"]:
                entry = e
                break
        if not entry or label in template:
            continue
        cls, data = refids.get(entry["rid"], (None, ""))
        if cls != "DataReference_Constant" or not audit.constant_is_empty(data):
            continue

        rel = os.path.relpath(asset, ROOT)
        name = audit.block_title(text, asset)

        # find the newest historical revision that still had a value
        payload = None
        for rev in recover.git("log", "--format=%H", "--follow", "--", rel).split()[:MAX_REVS]:
            old = recover.git("show", f"{rev}:{rel}")
            if not old:
                continue
            has, desc, guid = recover.value_of(old, label)
            if not has:
                continue
            old_refids = audit.parse_refids(old)
            for oe in audit.parse_prefab_fields(old):
                if oe["label"] == label:
                    ocls, odata = old_refids.get(oe["rid"], (None, ""))
                    if ocls == "DataReference_Constant" and not audit.constant_is_empty(odata):
                        payload = (odata, desc, guid, rev[:10])
                    break
            if payload:
                break

        if not payload:
            skipped.append((name, "sem valor em nenhuma revisão"))
            continue
        odata, desc, guid, rev = payload
        if guid != "?" and guid not in guid_map:
            skipped.append((name, f"sprite {desc} não existe mais (guid {guid})"))
            continue

        span = rid_data_span(text, entry["rid"])
        if not span:
            skipped.append((name, "rid não localizado no RefIds atual"))
            continue

        if apply:
            with open(asset, "w") as fh:
                fh.write(text[: span[0]] + odata + text[span[1] :])
        done.append((name, desc, rev))

    verb = "RESTAURADO" if apply else "RESTAURARIA (dry-run)"
    print(f"{game}: {verb} {len(done)}")
    for name, desc, rev in sorted(done):
        print(f"   {name:<34} <- {desc}   ({rev})")
    if skipped:
        print(f"\nnão tocado ({len(skipped)}):")
        for name, why in sorted(skipped):
            print(f"   {name:<34} {why}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
