#!/usr/bin/env python3
"""Static sanity check, game by game: visual fields that nothing ever feeds.

Answers three questions per game without running anything:

  1. UNFED     - a [VisualField] property bound to an *empty* constant. The widget is built, the
                 property is set, and the value handed over is nothing: null sprite, empty string,
                 zero. This is the shape behind "white square where the avatar goes" and "coloured
                 square instead of an icon", because Image.sprite = null still draws a quad.
  2. UNBOUND   - a [VisualField] property with no DataReference entry at all in the block that owns
                 the prefab. Nothing can ever write it, so it shows the prefab default forever.
  3. FROZEN    - bound to a non-empty constant. Legitimate for genuinely static art, suspicious when
                 the game's rules say the value should vary (per player, per round, per suit...).
                 Reported separately because only a human read of the game decides which it is.

Plus a prefab-side check:

  4. NULLREF   - a [SerializeField] reference left at {fileID: 0} in the prefab while the C# actually
                 dereferences it. Unity does not complain; the code either NREs or silently skips.

How the binding works (verified in VisualBlock.cs / DataReference.cs):
  VisualBlock.DefinePrefabFields reflects over [VisualField] properties and stores one DataReference
  per property, keyed by `label` = property name, in prefabFields (legacy) or
  templatePrefabFields + runtimePrefabFields (migrated). Each carries `selectedContext` and a `rid`
  into the asset's `references: RefIds:` payload, where DataReference_Constant keeps the literal.
  At runtime VisualBlock.SetupValueOnPresenter matches label -> PropertyInfo and calls SetValue.

Usage:
  python3 Scripts/audit_prefab_visual_fields.py                 # every game
  python3 Scripts/audit_prefab_visual_fields.py SecretHitler    # one game
  python3 Scripts/audit_prefab_visual_fields.py --frozen        # include the FROZEN section
"""

import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "Assets")
GAMES_DIR = os.path.join(ASSETS, "App", "Games")

# Unity writes an empty constant as blank valueByte plus an "Nothing (Type)" description.
EMPTY_DESC = re.compile(r"^Nothing\b")


def walk_files(base, suffix):
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in ("Library", "Temp", "obj", "Logs")]
        for fn in filenames:
            if fn.endswith(suffix):
                yield os.path.join(dirpath, fn)


def build_guid_map():
    """guid -> asset path, for every .meta under Assets."""
    guids = {}
    for meta in walk_files(ASSETS, ".meta"):
        try:
            with open(meta, "r", errors="ignore") as fh:
                for line in fh:
                    if line.startswith("guid:"):
                        guids[line.split()[1].strip()] = meta[: -len(".meta")]
                        break
        except OSError:
            continue
    return guids


# ---------------------------------------------------------------- C# side


CS_CACHE = {}


def parse_cs(path):
    """Return (visual_props, serialized_fields, body) for a C# file."""
    if path in CS_CACHE:
        return CS_CACHE[path]
    try:
        with open(path, "r", errors="ignore") as fh:
            text = fh.read()
    except OSError:
        CS_CACHE[path] = ([], [], "")
        return CS_CACHE[path]

    # Strip comments so a commented-out attribute is never counted as live wiring.
    stripped = re.sub(r"//[^\n]*", "", text)
    stripped = re.sub(r"/\*.*?\*/", "", stripped, flags=re.S)

    visual_props = re.findall(
        r"\[\s*VisualField[^\]]*\]\s*(?:public|internal|protected)?\s*[\w<>\[\],\s\.]+?\s+(\w+)\s*(?:\{|=>)",
        stripped,
    )

    serialized = []
    # Attributes may precede or follow [SerializeField] on the same declaration, so capture the whole
    # run and pull [ShowIf(nameof(flag))] out of it: that attribute states outright that the field is
    # conditional, which is the difference between a forgotten wire and a switched-off feature.
    for m in re.finditer(
        r"((?:\[[^\]]*\]\s*)*)\[\s*SerializeField[^\]]*\]\s*((?:\[[^\]]*\]\s*)*)"
        r"(?:public|private|protected|internal)?\s*"
        r"([\w<>\[\],\s\.]+?)\s+([\w\s,]+?)\s*;",
        stripped,
    ):
        attrs = (m.group(1) or "") + (m.group(2) or "")
        ftype, names = m.group(3).strip(), m.group(4)
        cond = re.search(r"ShowIf\s*\(\s*(?:nameof\s*\(\s*(\w+)\s*\)|\"(\w+)\")", attrs)
        showif = (cond.group(1) or cond.group(2)) if cond else None
        for name in names.split(","):
            name = name.strip()
            if name:
                serialized.append((name, ftype, showif))

    CS_CACHE[path] = (visual_props, serialized, stripped)
    return CS_CACHE[path]


def field_is_used(body, name):
    """True if the identifier appears anywhere beyond its own declaration."""
    return len(re.findall(r"\b" + re.escape(name) + r"\b", body)) > 1


def field_is_guarded(body, name):
    """True if the code null-checks the member before using it.

    Deliberately generous: `?.`, `== null`, `!= null`, `is null`, or a bare `if (x)`. A guarded field
    left null in the prefab is a designer's "this variant has no trail" - not a defect. Being generous
    here is what keeps the report readable; the cost is missing a guard that is present but wrong.
    """
    n = re.escape(name)
    patterns = [
        rf"\b{n}\s*\?\s*[.\[]",
        rf"\b{n}\s*[!=]=\s*null",
        rf"null\s*[!=]=\s*\b{n}\b",
        rf"\b{n}\s+is\s+(not\s+)?null",
        rf"if\s*\(\s*!?\s*{n}\s*\)",
        rf"\b{n}\s*\?\?",
    ]
    return any(re.search(p, body) for p in patterns)


# Types whose absence is visible on screen. A null Sprite/Material is the worst case: Unity's
# Image still renders a quad in the tint colour, which is the "white square where the avatar
# should be" artefact. Text going blank is milder but still a visible hole.
DRAWN_TYPES = {"Sprite", "Material", "Texture", "Texture2D"}
TEXT_TYPES = {"String", "LocalizedString", "AppText"}
VISUAL_TYPES = DRAWN_TYPES | TEXT_TYPES


def visual_property_setter(body, prop):
    """The setter body of a [VisualField] property, or '' when it is auto-implemented."""
    m = re.search(
        r"\[\s*VisualField[^\]]*\][^;{]*?\b" + re.escape(prop) + r"\s*\{(.*?)\n    \}",
        body,
        re.S,
    )
    if not m:
        return ""
    inner = m.group(1)
    sm = re.search(r"\bset\b\s*\{(.*)", inner, re.S)
    return sm.group(1) if sm else inner


# ------------------------------------------------------------- asset side


def parse_refids(text):
    """rid -> (class name, raw data block)."""
    out = {}
    sec = text.find("\n    RefIds:")
    if sec < 0:
        return out
    chunk = text[sec:]
    # No \n after the closing brace: consuming it would leave the lookahead nothing to match on for
    # an entry whose data block is empty, so that entry would swallow the next one. rid -2 is always
    # first and always empty, which meant the first real reference in every asset went missing.
    for m in re.finditer(
        r"\n    - rid: (-?\d+)\n      type: \{class: ([^,]*),[^}]*\}(.*?)(?=\n    - rid: |\Z)",
        chunk,
        re.S,
    ):
        out[m.group(1)] = (m.group(2).strip(), m.group(3))
    return out


def constant_is_empty(data_block):
    """An empty DataReference_Constant: no bytes and a 'Nothing (...)' description."""
    vb = re.search(r"^[ \t]*valueByte:[ \t]*(.*)$", data_block, re.M)
    desc = re.search(r"^[ \t]*overrideDescription:[ \t]*(.*)$", data_block, re.M)
    readable = re.search(r"^[ \t]*_readableValue:[ \t]*(.*)$", data_block, re.M)
    has_bytes = bool(vb and vb.group(1).strip())
    has_readable = bool(readable and readable.group(1).strip())
    says_nothing = bool(desc and EMPTY_DESC.match(desc.group(1).strip()))
    if has_bytes or has_readable:
        return False
    return says_nothing or not (has_bytes or has_readable)


def parse_prefab_fields(text):
    """Every DataReference entry across the three list fields."""
    entries = []
    for list_name in ("prefabFields", "templatePrefabFields", "runtimePrefabFields"):
        m = re.search(r"\n  " + list_name + r":\s*(\[\]|\n)", text)
        if not m or m.group(1) == "[]":
            continue
        start = m.end()
        block = []
        for line in text[start:].split("\n"):
            if line.startswith("  ") and not line.startswith("   ") and line.strip().endswith(":"):
                break
            if line and not line.startswith("  "):
                break
            block.append(line)
        chunk = "\n".join(block)
        for entry in re.finditer(
            r"^  - selectedContext:\s*(.*?)$(.*?)(?=^  - selectedContext:|\Z)", chunk, re.M | re.S
        ):
            ctx = entry.group(1).strip()
            body = entry.group(2)
            label = re.search(r"^[ \t]*label:[ \t]*(.*)$", body, re.M)
            rid = re.search(r"^[ \t]*- rid:[ \t]*(-?\d+)[ \t]*$", body, re.M)
            from_flow = re.search(r"^[ \t]*valueComeFromFlow:[ \t]*(\d)", body, re.M)
            tstr = re.search(r"^[ \t]*typeString:[ \t]*([\w\.\+]+)", body, re.M)
            if not label:
                continue
            entries.append(
                {
                    "label": label.group(1).strip(),
                    "context": ctx,
                    "rid": rid.group(1) if rid else None,
                    "from_flow": bool(from_flow and from_flow.group(1) == "1"),
                    "type": tstr.group(1).split(".")[-1] if tstr else "?",
                    "list": list_name,
                }
            )
    return entries


PLACEHOLDER_SPRITES = {"no_image"}


def prefab_default_sprites(prefab_path, guid_map):
    """Sprite file names the prefab's Image components fall back to when nothing feeds them.

    This is what decides whether an unfed Sprite matters. VisualBlock.SetPropertyValue ends with
    `if (value != null) { ... SetValue ... }`, so an empty constant does not null the sprite - it
    simply never writes the property, and whatever the prefab authored stays on screen. The generic
    ImageWidget authors `no_image.png`, so an unfed block renders a literal "no image" placeholder
    as if it were art.
    """
    names = set()
    try:
        with open(prefab_path, "r", errors="ignore") as fh:
            text = fh.read()
    except OSError:
        return names
    for gm in re.finditer(r"m_Sprite: \{fileID: \d+, guid: (\w+)", text):
        path = guid_map.get(gm.group(1))
        if path:
            names.add(os.path.splitext(os.path.basename(path))[0])
    if re.search(r"m_Sprite: \{fileID: 0\}", text):
        names.add("(null)")
    return names


def prefab_guid_of_block(text):
    """(guid, root GameObject fileID) the block instantiates."""
    m = re.search(r"\n  prefab:\n    gameObject: \{fileID: (\d+), guid: (\w+)", text)
    return (m.group(2), m.group(1)) if m else (None, None)


def template_field_names(text, refids):
    """Field names carried by a typed WidgetTemplateData, if the block uses one.

    Migrated blocks move their static configuration out of templatePrefabFields into a typed
    *WidgetTemplateData object (VisualBlock.ApplyTypedWidgetTemplate), leaving templatePrefabFields
    empty. Without this, every property on such a block looks unbound when it is simply configured
    somewhere else - which was 35 phantom findings on BDB_Cards alone.
    """
    m = re.search(r"\n  widgetTemplateData:\n    rid: (-?\d+)", text)
    if not m or m.group(1) == "-2":
        return set()
    _cls, data = refids.get(m.group(1), (None, ""))
    return set(re.findall(r"^ {8}(\w+):", data, re.M))


def block_title(text, path):
    """Prefer the authored name - it is the only clue to what the block is on screen.

    `title` is usually blank on these assets, and the file name is a hash (WidgetBlock#496a). Unity's
    m_Name carries what a designer actually called it (CarouselBGWidgetBlock, HUDWidgetBlock), which
    is what makes a report of unfed fields actionable instead of a list of opaque ids.
    """
    for field in ("title", "m_Name"):
        m = re.search(r"^  " + field + r":[ \t]*(.*)$", text, re.M)
        if m and m.group(1).strip():
            return m.group(1).strip()
    return os.path.basename(path).replace(".asset", "")


# ------------------------------------------------------------ prefab side


def prefab_components(prefab_path, guid_map, root_id=None):
    """[(class_path, {field: raw_yaml_value})] for MonoBehaviours on the prefab.

    With root_id, only components attached to that GameObject are returned. A VisualBlock binds
    properties on the *root* presenter only, so walking child components invents findings: BDB_Cards'
    StickerButton sits on a child of StickerInventory.prefab and can never be bound by that block.
    """
    try:
        with open(prefab_path, "r", errors="ignore") as fh:
            text = fh.read()
    except OSError:
        return []

    allowed = None
    if root_id:
        go = re.search(
            r"\n--- !u!1 &" + re.escape(str(root_id)) + r"\b.*?\n(.*?)(?=\n--- !u!|\Z)", text, re.S
        )
        if go:
            allowed = set(re.findall(r"component: \{fileID: (\d+)\}", go.group(1)))

    comps = []
    for m in re.finditer(r"\n--- !u!\d+ &(\d+).*?\n(.*?)(?=\n--- !u!|\Z)", text, re.S):
        anchor, block = m.group(1), m.group(2)
        if not block.lstrip().startswith("MonoBehaviour:"):
            continue
        if allowed is not None and anchor not in allowed:
            continue
        gm = re.search(r"m_Script: \{fileID: \d+, guid: (\w+)", block)
        if not gm:
            continue
        cs = guid_map.get(gm.group(1))
        if not cs or not cs.endswith(".cs"):
            continue
        values = {}
        for line in block.split("\n"):
            fm = re.match(r"^  (\w+):[ \t]*(.*)$", line)
            if fm:
                values[fm.group(1)] = fm.group(2).strip()
        comps.append((cs, values))
    return comps


# ---------------------------------------------------------------- driver


def build_override_index():
    """guid of a nested prefab -> the property paths someone overrides on it.

    A prefab used inside another prefab or a scene keeps its own component fields at {fileID: 0} and
    receives the real reference through the parent's PrefabInstance m_Modifications. Reading only the
    component block therefore reports a perfectly wired field as missing - it accounted for 8 of the
    NULLREF findings here (ColonyGame's five `frontend` panels, Ludo's three token anchors).
    """
    index = defaultdict(set)
    pattern = re.compile(
        r"- target: \{fileID: \d+, guid: (\w+)[^}]*\}\s*\n\s*propertyPath: ([\w\.\[\]]+)\s*\n"
        r"\s*value:[^\n]*\n\s*objectReference: \{fileID: (\d+)"
    )
    for base, suffix in ((ASSETS, ".prefab"), (ASSETS, ".unity")):
        for path in walk_files(base, suffix):
            try:
                with open(path, "r", errors="ignore") as fh:
                    text = fh.read()
            except OSError:
                continue
            if "m_Modifications" not in text:
                continue
            for m in pattern.finditer(text):
                if m.group(3) != "0":  # an override that actually points at something
                    index[m.group(1)].add(m.group(2))
    return index


def build_sibling_index(guid_map):
    """(class path, field) -> (how many prefabs assign it, how many leave it null).

    The single best discriminator for a null serialized reference. Truc11HandPopupWidget leaves
    challenger/defender null while its two sibling prefabs fill them - and it also leaves `header`
    null, which is the field whose null-check gates the whole avatar section. A variant that
    deliberately drops a section looks identical to a forgotten wire until you compare siblings.
    """
    index = defaultdict(lambda: [0, 0])
    for prefab in walk_files(ASSETS, ".prefab"):
        for cs, values in prefab_components(prefab, guid_map):
            _props, serialized, _body = parse_cs(cs)
            for name, _ftype, _showif in serialized:
                raw = values.get(name)
                if raw is None:
                    continue
                if raw == "{fileID: 0}":
                    index[(cs, name)][1] += 1
                elif raw.startswith("{fileID:"):
                    index[(cs, name)][0] += 1
    return index


def audit_game(game_dir, guid_map, want_frozen, siblings=None, overrides=None):
    findings = {"unfed": [], "unbound": [], "frozen": [], "nullref": []}

    # --- block-driven checks
    for asset in walk_files(game_dir, ".asset"):
        try:
            with open(asset, "r", errors="ignore") as fh:
                text = fh.read()
        except OSError:
            continue
        if "prefabFields" not in text:
            continue

        entries = parse_prefab_fields(text)
        if not entries:
            continue
        refids = parse_refids(text)
        title = block_title(text, asset)
        template_fields = template_field_names(text, refids)

        pguid, proot = prefab_guid_of_block(text)
        prefab_path = guid_map.get(pguid) if pguid else None
        prefab_name = os.path.basename(prefab_path) if prefab_path else "(no prefab)"

        # Bodies of every presenter class on this block's prefab, so a binding can be judged
        # against the C# that consumes it rather than in the abstract.
        comp_bodies = []
        if prefab_path and prefab_path.endswith(".prefab"):
            for cs, _vals in prefab_components(prefab_path, guid_map, proot):
                props, _sf, body = parse_cs(cs)
                comp_bodies.append((cs, props, body))

        bound_labels = set()
        for e in entries:
            bound_labels.add(e["label"])
            if e["from_flow"] or e["context"] != "Constant":
                continue  # fed dynamically - fine
            cls, data = refids.get(e["rid"], (None, ""))
            if cls != "DataReference_Constant":
                continue

            if not constant_is_empty(data):
                if want_frozen and e["type"] in VISUAL_TYPES:
                    findings["frozen"].append((title, prefab_name, e["label"], e["type"]))
                continue

            # An empty constant is the NORMAL state for a field the block simply does not
            # override - most booleans and numbers sit like this on purpose. It only matters
            # when the value would have been drawn, and the consuming property uses it without
            # checking. Anything wider than this drowns the report: SecretHitler alone has 383
            # empty constants, of which 225 are booleans nobody ever intended to set.
            if e["type"] not in VISUAL_TYPES:
                continue
            if e["label"] in template_fields:
                continue  # configured by the typed template instead
            for cs, props, body in comp_bodies:
                if e["label"] not in props:
                    continue
                setter = visual_property_setter(body, e["label"])
                if setter and field_is_guarded(setter, "value"):
                    continue
                shows = ""
                if e["type"] in DRAWN_TYPES and prefab_path:
                    defaults = prefab_default_sprites(prefab_path, guid_map)
                    placeholders = defaults & (PLACEHOLDER_SPRITES | {"(null)"})
                    shows = ", ".join(sorted(placeholders or defaults)) or "(none)"
                findings["unfed"].append(
                    (title, prefab_name, e["label"], e["type"], shows)
                )

        # [VisualField] properties the block has no entry for at all
        for cs, props, _body in comp_bodies:
            for p in props:
                if p not in bound_labels and p not in template_fields:
                    findings["unbound"].append(
                        (title, prefab_name, p, os.path.relpath(cs, ROOT))
                    )

    # --- prefab-driven check: serialized refs left null but dereferenced
    guid_of = {v: k for k, v in guid_map.items()}
    for prefab in walk_files(game_dir, ".prefab"):
        overridden = (overrides or {}).get(guid_of.get(prefab), set())
        for cs, values in prefab_components(prefab, guid_map):
            props, serialized, body = parse_cs(cs)
            for name, ftype, showif in serialized:
                raw = values.get(name)
                if raw is None:
                    continue
                if raw != "{fileID: 0}":
                    continue
                # [ShowIf(flag)] with the flag off in this prefab: the feature is switched off, so
                # the null is the authored state, not a missing wire (Hanabi's selection frames).
                if showif and values.get(showif) in ("0", "False", "false"):
                    continue
                if name in overridden:
                    continue  # wired by whoever nests this prefab
                if not field_is_used(body, name):
                    continue
                if field_is_guarded(body, name):
                    continue  # optional by design (no trail on this variant, etc.)
                assigned, nulled = (siblings or {}).get((cs, name), [0, 0])
                findings["nullref"].append(
                    (
                        os.path.basename(prefab),
                        os.path.basename(cs).replace(".cs", ""),
                        name,
                        ftype,
                        f"{assigned} outros prefabs preenchem / {nulled} deixam nulo",
                    )
                )

    return findings


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    want_frozen = "--frozen" in sys.argv

    guid_map = build_guid_map()
    siblings = build_sibling_index(guid_map)
    overrides = build_override_index()

    games = sorted(
        d for d in os.listdir(GAMES_DIR) if os.path.isdir(os.path.join(GAMES_DIR, d))
    )
    if args:
        wanted = {a.lower() for a in args}
        games = [g for g in games if g.lower() in wanted]
        if not games:
            print(f"no game matched {args}; available: {', '.join(sorted(os.listdir(GAMES_DIR)))}")
            return 1

    totals = defaultdict(int)
    for game in games:
        f = audit_game(os.path.join(GAMES_DIR, game), guid_map, want_frozen, siblings, overrides)
        count = sum(len(v) for k, v in f.items() if k != "frozen" or want_frozen)
        for k, v in f.items():
            totals[k] += len(v)
        if not count:
            print(f"\n=== {game}: clean")
            continue

        print(f"\n=== {game}")
        if f["unfed"]:
            print(f"  UNFED ({len(f['unfed'])}) - empty constant, drawn type, setter has no guard:")
            for title, prefab, label, ftype, shows in sorted(set(f["unfed"])):
                tail = f"   -> shows: {shows}" if shows else ""
                print(f"    {title:<30} {prefab:<30} .{label} : {ftype}{tail}")
        if f["unbound"]:
            print(f"  UNBOUND ({len(f['unbound'])}) - [VisualField] with no binding at all:")
            for title, prefab, label, cs in sorted(set(f["unbound"])):
                print(f"    {title:<34} {prefab:<34} .{label}   ({cs})")
        if f["nullref"]:
            print(f"  NULLREF ({len(f['nullref'])}) - serialized ref null in prefab but used in code:")
            for prefab, cls, name, ftype, sib in sorted(set(f["nullref"])):
                print(f"    {prefab:<34} {cls:<26} {name} : {ftype}   [{sib}]")
        if want_frozen and f["frozen"]:
            print(f"  FROZEN ({len(f['frozen'])}) - constant, never varies at runtime:")
            for title, prefab, label, _a in sorted(set(f["frozen"])):
                print(f"    {title:<34} {prefab:<34} .{label}")

    print("\n" + "=" * 70)
    print(
        f"TOTAL  unfed={totals['unfed']}  unbound={totals['unbound']}  "
        f"nullref={totals['nullref']}" + (f"  frozen={totals['frozen']}" if want_frozen else "")
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
