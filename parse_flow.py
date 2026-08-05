#!/usr/bin/env python3
"""
parse_flow.py — Convert a CodeFlow .asset YAML file to human-readable pseudocode.

Usage:
    python3 Scripts/parse_flow.py Assets/App/Games/MauMau/Gameplay/MauMauFlow_playcard.asset
    python3 Scripts/parse_flow.py Assets/App/Games/MauMau/Gameplay/MauMauFlow_DealCards.asset -v

Flags:
    -v / --verbose   Show raw field dump for every node (useful when debugging unexpected logic)

The script maps every node to a class name using the .meta GUID map, traces control-flow
connections, and prints indented pseudocode.  It handles the 40 node types seen in Boardible
FlowBox assets; unknown nodes fall back to a generic "??? ClassName" display.

GUID is resolved from the GameBox source tree automatically (requires the project to be
present at the standard boardgames/ layout).
"""

import re
import sys
import os
import argparse
from collections import defaultdict

# ─────────────────────────────────────────────────────────────────────────────
#  GUID → ClassName map
#  Run   python3 Scripts/parse_flow.py --build-guid-map   to regenerate from
#  the live GameBox source (requires the GameBox folder to be present).
# ─────────────────────────────────────────────────────────────────────────────
GUID_CLASS = {
    # ── Confirmed from GameBox source (run --build-guid-map to regenerate) ──
    "0383602a7e8d549828876eb5ba17223f": "SameContext",
    "08757d43096fb4502974b294f0e054d9": "GetPieceNode",
    "0b333d44874d54e0485ea00fb04e2359": "GetImageNode",
    "0de09840479f7e7468ee991e93b9a9fe": "ConditionExpressionNode",
    "1e371adefe1ac4e25926ecb0e53bfa03": "WhileNode",
    "330e2ec5df987d946811fa4a1493549e": "CounterNode",
    "3448d16d602902c479a464217009981e": "PlayerActionContext",
    "371f47358e6322b468e1b0a8894b9d3c": "ResetCounterNode",
    "38633be5df6944fee99b3e3e86f70b7b": "SetContextNode",
    "38df85e35c90247aa80cb9318e1e89c4": "GetBoolNode",
    "3f8d5c16f90d171418eefc378274bedc": "SetDataNode",
    "472a29e0681f8462db93771a90265e55": "PoolActionNode",
    "4869d2806ba614c4fa25c3d3d0662b15": "GetStaticFieldNode",
    "4e8c2047af8a441f79a23f3a9c155bfc": "EvalDataNode",
    "54fa097a985274a468b6822786c8fd7d": "EachPlayerNode",
    "62efc604e72d14f27989bde1b39ebad5": "SetListNode",
    "6f61b386450ab43eaa55ed586e216f65": "FunctionCallerNode",
    "70649ca79730b2443a8c4b4089fa5dd8": "ActionRpcNode",
    "719e31ee5ec854654a9067d844027304": "ConditionEvalNode",
    "7acc81df7679b11489f83c15233a3d7c": "AndNode",
    "893d3bf337195214daf48500d29f2a7b": "ShowAnimatedBanner",
    "9f473f94d4bc14d45ac648d5639c0ca5": "IfNode",
    "ad393ec518f018c4f9c527befb3d49b5": "ContextCondtion",   # typo matches real class name
    "2cff4a5c0a8c8406880ce2e896b6b3f7": "MathNode",
    "361b93d1c5a44471487b84f5556fa718": "SwitchNode",
    "71c3cd55828f79a49a094bf7b6be4a4d": "SkipActionContext",
    "945230223d50346cd99c53039f917784": "OffsetContext",
    "a7e42b4df420d9d45bb4a28074358894": "EachTeamNode",
    "ad3dd9c150b7b443ba20ddf67a5506ce": "FunctionHeaderNode",  # was mislabeled NeutralContext; guid actually belongs to FunctionHeaderNode.cs
    "b0e826a3a43484b1a9e36a88cda12854": "GetStringNode",
    "b6bc9b9212eb84f189fcb5f91bc4b167": "ShowAnimation",
    "b7cffd7b719084aadaf09ef372731a6e": "GetPoolNode",
    "ba6cdc5dd9755d447923abee9179e8c1": "OrNode",
    "bf0d2529accf444eb978d7b7ca6762b6": "SubFlowBox",
    "c8056dd2ce05944fea390fc6af2c2d3d": "GetDataNode",
    "c89474928759dec4c871457ee7b14079": "NeutralContext",    # second NeutralContext variant
    "d2ae055e4a3ac4396add21176e966b3e": "GetContextNode",
    "dc3c84cd7b925da40b1ebdb56e2a53c2": "InvokeActionNode",
    "e13fa6d888b3746e8862f788a9913d16": "ListPoolBlock",
    "ee856fac8509b4c6dbb62394ee13e129": "GetListNode",
    "ef0a18e4e82c043ddb556174a213f827": "ShowReaction",
    "feb011d96c612473caa111ff0e3f3d0e": "PieceActionNode",
    "46ce5845473299643b24a6ccf1c1fdad": "ListenerNode",   # "Thread Header" — entry point of a named concurrent thread
    "2243209333df82b439b884da110d49f3": "EmitterNode2",  # "Thread Caller" — fires Controller.StartEventThread(threadNode)
    "5e1acf2d10bb66749b0bb6818d7c3f5b": "EmitterNode",   # older "Thread Caller" variant — same Controller.StartEventThread(threadNode) semantics, one extra ready-tick
    "4e628d27406c64481a5dbcfcf1417769": "TimerNode",      # blocks until minValue/maxValue reached, writing live value to a data field each tick
    "c30b992cc0eae4d158b68b94cc8fc675": "MathExpressionNode",  # evaluates expressionEval against bound "variables" inputs, exposes result via "output"
    "eba82053cdf71496187b35d7a4d429e1": "TableStateActionNode",  # "Actions/Table State" — presenter.TurnOnState(stateName) on a TableBlock
    "83eef0c40ff8d4d818b2e12aed8478bc": "GetIntNode",  # literal int, or RandomUtil.GetSyncedInt(min, max+1) when isRandom
    "fe932268c708a4d539f906cfbe39c0a8": "EachPieceNode",  # foreach over a pool's pieces
    "330982cb209ed1e4782e7d42a860b8ed": "StartNode",  # root flow's own entry point (not a FunctionHeaderNode)
    "1a071137c906f784e96352893624f0ef": "EndNode",    # terminal marker, no outgoing "next"
    "ad076f3a656fc9242bf8519cd9b859d4": "CheckAnyPremiumNode",  # outputs bool "hasPremium"
    "b940e56075b00401cbef69cffccb2584": "GetEnumValueNode",
    "d2a70e38d21091b4ba9a82afd913ba1c": "ShowNativePopupNode",
    "7127bedbf15d203469ec0401b047943d": "WaitPremiumNode",  # blocks until a premium purchase flow resolves, outputs bool
}

# Human-readable scope labels (DataRepoScope enum)
# DataRepoScope enum values (confirmed from DataRepositoryAttribute.cs)
# Player=0, Team=1, Neutral=2, PlayerList=3, TeamList=4
SCOPE_LABEL = {
    "0": "player",
    "1": "team",
    "2": "neutral",
    "3": "player-list",
    "4": "team-list",
    "16": "context",
    "32": "piece",
}

# ConditionEvalNode.scope is a [Flags] ContextField, NOT a DataRepoScope — a different
# encoding entirely (confirmed from ContextData.cs). Using SCOPE_LABEL for it silently
# mislabels "neutral" (0) as "player" and vice versa. Only the 3 field-bearing values are
# meaningful here (Pool/Piece/etc. branch to customField, not field, in ConditionEvalNode).
CONTEXT_FIELD_SCOPE_LABEL = {
    "0": "neutral",
    "1": "team",
    "2": "player",
}

# BoolManipulation enum (confirmed from PieceActionNode.cs)
MANIP_LABEL = {
    "0": "Invert",
    "1": "False (ENABLE/Remove)",
    "2": "True (DISABLE/Add)",
}

# ─────────────────────────────────────────────────────────────────────────────
#  YAML parsing helpers
# ─────────────────────────────────────────────────────────────────────────────
# Unity "YAML" is not standard — we parse it with regex rather than PyYAML.

def parse_asset(path: str) -> dict:
    """
    Returns dict: fileID (str) → {guid, class_name, name, fields, outgoing, body}

    outgoing: dict port_name → list of connected node fileIDs (direction=1 ports only)
    These are the forward/outgoing connections for flow traversal.
    """
    with open(path, encoding="utf-8") as f:
        content = f.read()

    # Unity YAML uses 64-bit signed integers as local fileIDs (e.g. -9032502308065341722)
    doc_pattern = re.compile(r"^--- !u!\d+ &(-?\d+)", re.MULTILINE)
    splits = list(doc_pattern.finditer(content))

    nodes = {}
    for i, match in enumerate(splits):
        file_id = match.group(1)
        start = match.end()
        end = splits[i + 1].start() if i + 1 < len(splits) else len(content)
        body = content[start:end]

        guid = _extract_guid(body)
        class_name = GUID_CLASS.get(guid, f"?({guid[:8]})")
        node_name = _field(body, "m_Name") or ""

        fields = _extract_fields(body)
        outgoing = _parse_outgoing_ports(body)

        nodes[file_id] = {
            "guid": guid,
            "class": class_name,
            "name": node_name,
            "fields": fields,
            "outgoing": outgoing,   # port_name → [fileID, ...]
            "body": body,
        }

    return nodes


def _extract_guid(body: str) -> str:
    m = re.search(r"m_Script:\s*\{[^}]*guid:\s*([0-9a-f]+)", body)
    return m.group(1) if m else ""


def _field(body: str, name: str) -> str:
    """Extract a top-level scalar field value from a MonoBehaviour body."""
    m = re.search(rf"^\s{{2,4}}{re.escape(name)}:\s+(.+)$", body, re.MULTILINE)
    return m.group(1).strip() if m else ""


def _yaml_list(body: str, name: str) -> list:
    """Extract a simple top-level YAML string list like 'conditions:\\n  - A\\n  - B'."""
    m = re.search(rf"^\s{{2}}{re.escape(name)}:\s*\n((?:\s{{2,4}}-\s*.*\n?)+)", body, re.MULTILINE)
    if not m:
        return []
    return [line.split("-", 1)[1].strip() for line in m.group(1).splitlines() if line.strip().startswith("-")]


def _extract_fields(body: str) -> dict:
    """Collect all top-level scalar fields from a MonoBehaviour body."""
    result = {}
    for m in re.finditer(r"^\s{2}(\w+):\s+([^\n{}\[\]]+)$", body, re.MULTILINE):
        result[m.group(1)] = m.group(2).strip()
    return result


def _parse_outgoing_ports(body: str) -> dict:
    """
    Parse the ports.values section and return each named port's connections.

    Unity xNode stores ports as a parallel keys/values structure. _direction indicates
    whether THIS port is an input (0) or output (1) socket on THIS node — but that
    convention is only reliable for flow-chain ports ("next" is 1, "previous" is 0).
    For data-pull ports (SetDataNode's "value", PieceActionNode's "pieceOrPool", etc.)
    direction is 0 even though we still need to resolve what feeds them — filtering on
    direction==1 silently dropped these connections entirely (e.g. it made a live
    "neutral.firstTeam <= GetListNode.first" connection look like a literal "0" default).
    Each field name appears exactly once per node, so capturing every direction is safe —
    there's no risk of an outgoing and incoming entry colliding under the same key.

    Returns: {port_name: [fileID, ...]}
    """
    # Locate the values: section inside ports:
    ports_block_m = re.search(r"^\s{2}ports:\s*\n(.*?)(?=^\s{2}\w)", body, re.MULTILINE | re.DOTALL)
    if not ports_block_m:
        return {}
    ports_block = ports_block_m.group(1)

    # Extract the values: subsection
    values_m = re.search(r"^\s{4}values:\s*\n(.*)", ports_block, re.MULTILINE | re.DOTALL)
    if not values_m:
        return {}
    values_block = values_m.group(1)

    # Split into individual port entries (each starts with "    - _fieldName:")
    # Use a lookahead to keep the separator
    entries = re.split(r"(?=^\s{4}-\s+_fieldName:)", values_block, flags=re.MULTILINE)

    result = {}
    for entry in entries:
        fname_m = re.search(r"_fieldName:\s+(.+)$", entry, re.MULTILINE)
        if not fname_m:
            continue
        field_name = fname_m.group(1).strip()

        # Extract all connected node fileIDs (signed 64-bit ints) AND, when present, their
        # guid. Unity only emits a guid on an object reference when it crosses an asset-file
        # boundary — same-file (local) references are serialized as bare {fileID: X}. So a
        # present guid always means "this connection's real target lives in another file,"
        # and the fileID alone is meaningless (or worse, misleading — see the fileID 11400000
        # collision bug in parse-flow-port-resolution-bugs memory). Preferring guid-when-present
        # as the resolution key fixes that class of bug and is what makes per-node-split
        # formats (every node in its own file, e.g. QDC) resolvable at all: every real
        # connection there carries a guid.
        #
        # Negative lookbehind excludes "_node: {fileID: ...}" (the port's own owner-node
        # metadata, which always precedes "connections:") so only the real "node:" targets
        # inside "connections:" entries are matched. Without it, ids[0] was the port's own
        # owning node (a self-reference), making every traversal look "already visited".
        node_refs = [
            (m.group(1), m.group(2) or "")
            for m in re.finditer(r"(?<!_)\bnode:\s*\{fileID:\s*(-?\d+)(?:,\s*guid:\s*([0-9a-f]+))?", entry)
        ]
        node_ids = [(guid or fid) for fid, guid in node_refs if fid != "0"]
        if node_ids:
            result[field_name] = node_ids

    return result


def _port(nodes: dict, file_id: str, port_name: str) -> str:
    """Return the first outgoing fileID for the given port, or ''."""
    outgoing = nodes.get(file_id, {}).get("outgoing", {})
    ids = outgoing.get(port_name, [])
    return ids[0] if ids else ""


def _obj_ref(body: str, field_name: str):
    """
    Extract fileID/guid from a plain scalar object-reference field like
    'functionNode: {fileID: X, guid: Y, type: Z}' or 'threadNode: {fileID: X}'.
    These are NOT xNode ports (they don't appear in the ports.values section),
    so _port()/_port_list() can never resolve them — this reads the raw field directly.
    Returns (fileID, guid) — guid is '' when the reference is same-file (no guid emitted).
    """
    m = re.search(rf"^\s{{2,4}}{re.escape(field_name)}:\s*\{{fileID:\s*(-?\d+)(?:,\s*guid:\s*([0-9a-f]+))?", body, re.MULTILINE)
    if not m:
        return "", ""
    return m.group(1), (m.group(2) or "")


def _port_list(nodes: dict, file_id: str, base_name: str) -> list:
    """
    Return all outgoing fileIDs for ordered step ports like 'steps 0', 'steps 1', ...
    Stops at the first missing index.
    """
    outgoing = nodes.get(file_id, {}).get("outgoing", {})
    result = []
    i = 0
    while True:
        key = f"{base_name} {i}"
        ids = outgoing.get(key, [])
        if not ids:
            break
        result.append(ids[0])
        i += 1
    return result


def _find_gameplay_root(path: str) -> str:
    """
    Walk up from `path` to the nearest ancestor directory named "Gameplay" — the
    per-game root under Assets/App/Games/<Game>/Gameplay/. Bounds the guid-index scan to
    one game's assets instead of the whole Assets/ tree (which the project's own terminal
    rules forbid recursively scanning — see .github/copilot-instructions.md).
    Falls back to the immediate parent directory if no "Gameplay" ancestor is found.
    """
    d = os.path.dirname(os.path.abspath(path))
    cur = d
    while True:
        if os.path.basename(cur) == "Gameplay":
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return d  # hit filesystem root without finding one — fall back
        cur = parent


def _build_guid_index(root_dir: str) -> dict:
    """guid -> .asset path, scanned from every *.asset.meta under root_dir."""
    index = {}
    for dirpath, _dirnames, filenames in os.walk(root_dir):
        for fn in filenames:
            if not fn.endswith(".asset.meta"):
                continue
            meta_path = os.path.join(dirpath, fn)
            asset_path = meta_path[: -len(".meta")]
            if not os.path.isfile(asset_path):
                continue
            try:
                with open(meta_path, encoding="utf-8") as f:
                    m = re.search(r"^guid:\s*([0-9a-f]+)", f.read(), re.MULTILINE)
            except OSError:
                continue
            if m:
                index[m.group(1)] = asset_path
    return index


def _extract_ref_list(content: str, field_name: str) -> list:
    """Extract guids from a top-level list of object refs like 'baseBlocks:\\n  - {fileID: X, guid: Y, type: Z}'."""
    m = re.search(rf"^\s{{2}}{re.escape(field_name)}:\s*\n((?:\s{{2,6}}-\s*\{{.*\}}\n?)+)", content, re.MULTILINE)
    if not m:
        return []
    return re.findall(r"guid:\s*([0-9a-f]+)", m.group(1))


def load_flow_nodes(path: str) -> dict:
    """
    Parse a flow .asset file, transparently merging in any nodes it references via a
    top-level 'baseBlocks' list — the per-node-split format some games use (every node
    serialized to its own file under blocks/<name>/, e.g. QDC) instead of Charades-style
    inline multi-document files. Safe to call on either format: if there's no 'baseBlocks'
    field, this is equivalent to plain parse_asset().

    External nodes are keyed by their own guid (known directly from the baseBlocks list,
    no need to re-read their .meta) — this lines up with _parse_outgoing_ports/_obj_ref,
    which now resolve any guid-bearing reference by guid first.
    """
    nodes = parse_asset(path)

    with open(path, encoding="utf-8") as f:
        content = f.read()

    block_guids = _extract_ref_list(content, "baseBlocks")
    if not block_guids:
        return nodes

    gameplay_root = _find_gameplay_root(path)
    guid_index = _build_guid_index(gameplay_root)

    for guid in block_guids:
        if guid in nodes:
            continue
        block_path = guid_index.get(guid)
        if not block_path:
            continue  # referenced but not found under this game's Gameplay root — leave unresolved
        block_nodes = parse_asset(block_path)
        # Per-node-split files hold exactly one document, conventionally at fileID 11400000.
        node = block_nodes.get("11400000") or (next(iter(block_nodes.values())) if block_nodes else None)
        if node:
            nodes[guid] = node

    return nodes


# ─────────────────────────────────────────────────────────────────────────────
#  Pseudocode printer
# ─────────────────────────────────────────────────────────────────────────────
SKIP_CLASSES = {"ShowReactionNode", "ShowAnimatedBanner", "ShowAnimation", "GetImageNode"}
DISPLAY_ONLY = {"GetImageNode", "ShowReactionNode", "ShowAnimatedBanner", "ShowAnimation"}


class Printer:
    def __init__(self, nodes: dict, verbose: bool = False, own_guid: str = ""):
        self.nodes = nodes
        self.verbose = verbose
        self.own_guid = own_guid
        self.visited = set()
        # Build index by class for quick lookup
        self._by_class = defaultdict(list)
        for fid, n in nodes.items():
            self._by_class[n["class"]].append(fid)

    def _resolve_ref(self, ref_fid: str, ref_guid: str):
        """
        Resolve an _obj_ref() (fileID, guid) pair to a node. When a guid is present the
        reference is cross-file by definition (see _parse_outgoing_ports) — look it up by
        guid, which is how externally-loaded per-node-split files are keyed in self.nodes
        (see load_flow_nodes). A guid that isn't in self.nodes is a genuinely external node
        we didn't load (a different subflow/graph entirely) — return None rather than
        falling back to fileID, since per-node-split files reuse fileID 11400000 for their
        sole object and a blind fileID fallback would collide with an unrelated local node.
        No guid means a same-file (local) reference — look up by fileID as before.
        Returns the node dict, or None if unresolved/external.
        """
        if not ref_fid:
            return None
        if ref_guid:
            return self.nodes.get(ref_guid)
        return self.nodes.get(ref_fid)

    # Convenience wrappers that don't need self.nodes passed everywhere
    def _next(self, fid: str) -> str:
        return _port(self.nodes, fid, "next")

    def _steps(self, fid: str) -> list:
        return _port_list(self.nodes, fid, "steps")

    def _true_next(self, fid: str) -> str:
        return _port(self.nodes, fid, "trueNext")

    def _false_next(self, fid: str) -> str:
        return _port(self.nodes, fid, "falseNext")

    def _condition(self, fid: str) -> str:
        return _port(self.nodes, fid, "condition")

    def _fn_ref(self, fid: str):
        # FunctionCallerNode's target is a plain 'functionNode' object reference field,
        # not an xNode port — _port() can never see it. Returns (fileID, guid).
        return _obj_ref(self.nodes[fid]["body"], "functionNode")

    def _thread_ref(self, fid: str):
        # EmitterNode2's target is a plain 'threadNode' object reference field.
        return _obj_ref(self.nodes[fid]["body"], "threadNode")

    # ── Entry point ──────────────────────────────────────────────────────────

    def run(self, asset_name: str):
        print(f"\n{'='*70}")
        print(f"  {asset_name}")
        print(f"{'='*70}\n")

        # Print each function (FunctionHeaderNode) in document order. StartNode is the same
        # kind of entry point for a root flow that has no FunctionHeaderNode at all (root
        # flows call subflows via FunctionCallerNode but aren't themselves callable).
        headers = [(fid, n) for fid, n in self.nodes.items() if n["class"] in ("FunctionHeaderNode", "StartNode")]
        # Thread entry points (ListenerNode / "Thread Header") are independent execution
        # roots too — they're never reached by traversing from FunctionHeaderNode/StartNode,
        # only referenced indirectly via an EmitterNode2's threadNode field.
        threads = [(fid, n) for fid, n in self.nodes.items() if n["class"] == "ListenerNode"]

        if not headers and not threads:
            # Fall back: find NeutralContext as the root
            roots = [(fid, n) for fid, n in self.nodes.items() if n["class"] in ("NeutralContext", "SameContext")]
            for fid, node in roots:
                self._print_node(fid, indent=0)
            return

        for fid, node in headers:
            self.visited.clear()
            kind = "ROOT" if node["class"] == "StartNode" else "FUNCTION"
            title = node["name"] or "(unnamed function)"
            print(f"┌── {kind}: {title}")
            next_id = self._next(fid)
            if next_id:
                self._print_node(next_id, indent=1)
            print()

        for fid, node in threads:
            self.visited.clear()
            title = node["name"] or "(unnamed thread)"
            print(f"┌── THREAD: {title}")
            next_id = self._next(fid)
            if next_id:
                self._print_node(next_id, indent=1)
            print()

    # ── Node dispatch ────────────────────────────────────────────────────────

    def _print_node(self, fid: str, indent: int):
        if not fid or fid not in self.nodes:
            return
        if fid in self.visited:
            short = fid[:10] if len(fid) > 10 else fid
            print("  " * indent + f"↪ (already visited #{short})")
            return
        self.visited.add(fid)

        node = self.nodes[fid]
        cls = node["class"]
        name = node["name"]
        label = f'["{name}"] ' if name else ""
        pad = "  " * indent

        if self.verbose:
            print(f"{pad}# raw fields: {node['fields']}")
            print(f"{pad}# outgoing ports: {node['outgoing']}")

        dispatch = {
            "SetDataNode":               self._print_set_data,
            "GetDataNode":               self._print_get_data,
            "GetStringNode":             self._print_get_data,
            "GetBoolNode":               self._print_get_data,
            "GetStaticFieldNode":        self._print_get_data,
            "PieceActionNode":           self._print_piece_action,
            "PoolActionNode":            self._print_pool_action,
            "EachPlayerNode":            self._print_each_player,
            "EachTeamNode":              self._print_each_team,
            "EachPieceNode":             self._print_each_piece,
            "WhileNode":                 self._print_while,
            "IfNode":                    self._print_if,
            "ConditionEvalNode":         self._print_condition_eval,
            "ConditionExpressionNode":   self._print_condition_expression,
            "FunctionCallerNode":        self._print_function_caller,
            "GetPoolNode":               self._print_get_pool,
            "GetPieceNode":              self._print_get_piece,
            "GetContextNode":            self._print_get_context,
            "SetContextNode":            self._print_set_context,
            "PlayerActionContext":        self._print_pac,
            "NeutralContext":            self._print_neutral_context,
            "SameContext":               self._print_same_context,
            "EvalDataNode":              self._print_eval_data,
            "SetListNode":               self._print_set_list,
            "GetListNode":               self._print_get_list,
            "AndNode":                   self._print_logic_node,
            "OrNode":                    self._print_logic_node,
            "CounterNode":               self._print_counter,
            "ResetCounterNode":          self._print_reset_counter,
            "FunctionHeaderNode":        self._print_function_header,
            "InvokeActionNode":          self._print_invoke_action,
            "ActionRpcNode":             self._print_action_rpc,
            "ShowReaction":              self._print_visual_skip,
            "ShowAnimatedBanner":        self._print_visual_skip,
            "ShowAnimation":             self._print_visual_skip,
            "ContextCondtion":           self._print_context_condition,
            "SubFlowBox":                self._print_subflow_box,
            "GetImageNode":              self._print_visual_skip,
            "EmitterNode2":              self._print_emitter_node2,
            "EmitterNode":               self._print_emitter_node2,
            "ListenerNode":              self._print_listener_node,
            "TimerNode":                 self._print_timer_node,
            "MathExpressionNode":        self._print_math_expression,
            "SwitchNode":                self._print_switch,
            "TableStateActionNode":      self._print_table_state_action,
            "GetIntNode":                self._print_get_int,
            "StartNode":                 self._print_start_node,
            "EndNode":                   self._print_end_node,
        }

        handler = dispatch.get(cls)
        if handler:
            handler(fid, node, indent, pad, label)
        elif fid == "11400000" and cls.startswith("?("):
            # fileID 11400000 is Unity's conventional first-object slot — almost always the
            # asset's OWN root container (e.g. "CharadesFlow"), not a real flow step. A "next"
            # connection resolving here from ANOTHER file almost always means the true target
            # lives in a different .asset (the parser only compares fileID, not guid, so a
            # cross-file connection can collide with this number and "resolve" to the wrong
            # local node). Flag it instead of silently printing a bogus step.
            print(f"{pad}↪ (cross-file connection — target lives in another subflow .asset, not traced here)")
        else:
            print(f"{pad}??? {label}{cls} #{fid[:10]}")
            self._print_node(self._next(fid), indent)

    # ── Node printers ────────────────────────────────────────────────────────

    def _print_set_data(self, fid, node, indent, pad, label):
        body = node["body"]
        field = _field(body, "field")
        value = _field(body, "value")
        scope = SCOPE_LABEL.get(_field(body, "scope"), _field(body, "scope"))
        op = _field(body, "operation")
        # SetDataNode.SetOperation: Absolute=0, Add=1, Subtract=2 (SetDataNode.cs)
        OP_SYMBOL = {"0": "=", "1": "+=", "2": "-="}
        op_str = OP_SYMBOL.get(op, f"op{op}=")
        # Check if value comes from a connected node (dynamic value)
        src_fid = _port(self.nodes, fid, "value")
        if src_fid and src_fid in self.nodes:
            src = self.nodes[src_fid]
            value = f"<= {src['class']}({src['name'] or src_fid[:8]})"
        print(f"{pad}SET {label}{scope}.{field} {op_str} {value}")
        self._print_node(self._next(fid), indent)

    def _print_get_data(self, fid, node, indent, pad, label):
        body = node["body"]
        field = _field(body, "field") or _field(body, "m_FieldName")
        scope = SCOPE_LABEL.get(_field(body, "scope"), _field(body, "scope"))
        print(f"{pad}GET {label}{scope}.{field}")
        self._print_node(self._next(fid), indent)

    def _resolve_pool_name(self, fid: str) -> str:
        # PieceActionNode/PoolActionNode/GetPieceNode/GetPoolNode all reference their pool
        # via a plain scalar "poolBlock" object-ref field (cross-file, per-node-split like
        # visualBlock/functionNode/threadNode) — NOT a "pool"/"pieceOrPool" port. The
        # "pieceOrPool" port is a separate, usually-unused string-literal alternate input.
        pool_fid, pool_guid = _obj_ref(self.nodes[fid]["body"], "poolBlock")
        pool_node = self._resolve_ref(pool_fid, pool_guid)
        if pool_node:
            return pool_node.get("name") or pool_fid[:8]
        if pool_fid:
            return f"(external pool, guid={pool_guid[:8]})"
        return "pool"

    def _print_piece_action(self, fid, node, indent, pad, label):
        body = node["body"]
        # PieceActionNode/PoolActionNode both inherit EntityActionNode.actionName — there is
        # no separate numeric actionType field in the current source.
        action_name = _field(body, "actionName") or "?"
        pool_name = self._resolve_pool_name(fid)

        if action_name == "kSetState":
            # Read state manipulation fields from pieceStateManipulation
            manip_m = re.search(r"pieceState:\s+(\S+)\n\s+manipulation:\s+(\d+)", body)
            if manip_m:
                state = manip_m.group(1).strip()
                manip = MANIP_LABEL.get(manip_m.group(2), manip_m.group(2))
                print(f"{pad}PIECE {label}{pool_name}.SetState(\"{state}\", {manip})")
            else:
                print(f"{pad}PIECE {label}{pool_name}.SetState(?)")
        else:
            print(f"{pad}PIECE {label}{pool_name}.{action_name}")

        self._print_node(self._next(fid), indent)

    def _print_pool_action(self, fid, node, indent, pad, label):
        body = node["body"]
        action_name = _field(body, "actionName") or "?"
        pool_name = self._resolve_pool_name(fid)
        print(f"{pad}POOL {label}{pool_name}.{action_name}")
        self._print_node(self._next(fid), indent)

    def _print_each_player(self, fid, node, indent, pad, label):
        body = node["body"]
        list_name = _field(body, "listField") or "kOrder"
        steps = self._steps(fid)
        print(f"{pad}FOREACH player IN {list_name}: {label}")
        for s in steps:
            self._print_node(s, indent + 1)
        self._print_node(self._next(fid), indent)

    def _print_each_team(self, fid, node, indent, pad, label):
        body = node["body"]
        list_name = _field(body, "listField") or "kOrder"
        steps = self._steps(fid)
        print(f"{pad}FOREACH team IN {list_name}: {label}")
        for s in steps:
            self._print_node(s, indent + 1)
        self._print_node(self._next(fid), indent)

    def _print_each_piece(self, fid, node, indent, pad, label):
        pool_name = self._resolve_pool_name(fid)
        steps = self._steps(fid)
        print(f"{pad}FOREACH piece IN {pool_name}: {label}")
        for s in steps:
            self._print_node(s, indent + 1)
        self._print_node(self._next(fid), indent)

    def _print_while(self, fid, node, indent, pad, label):
        cond_fid = self._condition(fid)
        cond_str = self._summarize_condition(cond_fid)
        steps = self._steps(fid)
        print(f"{pad}WHILE {label}{cond_str}:")
        for s in steps:
            self._print_node(s, indent + 1)
        self._print_node(self._next(fid), indent)

    def _print_if(self, fid, node, indent, pad, label):
        cond_fid = self._condition(fid)
        if cond_fid:
            cond_str = self._summarize_condition(cond_fid)
        else:
            # Some IfNode instances take a plain bool from "inputBool" instead of a
            # ConditionNode chain hanging off "condition" (e.g. fed directly by
            # CheckAnyPremiumNode's "hasPremium" output) — fall back to describing that.
            bool_src_fid = _port(self.nodes, fid, "inputBool")
            if bool_src_fid and bool_src_fid in self.nodes:
                src = self.nodes[bool_src_fid]
                cond_str = f"{src['class']}({src.get('name') or bool_src_fid[:8]}).result"
            else:
                cond_str = "???"
        true_fid = self._true_next(fid)
        false_fid = self._false_next(fid)
        print(f"{pad}IF {label}{cond_str}:")
        if true_fid:
            print(f"{pad}  [TRUE]")
            self._print_node(true_fid, indent + 2)
        if false_fid:
            print(f"{pad}  [FALSE]")
            self._print_node(false_fid, indent + 2)
        self._print_node(self._next(fid), indent)

    def _print_condition_eval(self, fid, node, indent, pad, label):
        body = node["body"]
        field = _field(body, "field") or _field(body, "customField")
        op = _field(body, "operation")
        value = _field(body, "value")
        scope = CONTEXT_FIELD_SCOPE_LABEL.get(_field(body, "scope"), _field(body, "scope"))
        # Comparator enum (confirmed from Comparator.cs): more_equal, more, equal, less, less_equal, not_equal
        OPS = {"0": ">=", "1": ">", "2": "==", "3": "<", "4": "<=", "5": "!="}
        op_str = OPS.get(op, op)
        print(f"{pad}COND {label}{scope}.{field} {op_str} {value}")
        self._print_node(self._next(fid), indent)

    def _print_condition_expression(self, fid, node, indent, pad, label):
        body = node["body"]
        expression = _field(body, "expression") or "..."
        print(f"{pad}COND_EXPR {label}{expression}")
        self._print_node(self._next(fid), indent)

    def _print_function_caller(self, fid, node, indent, pad, label):
        fn_fid, fn_guid = self._fn_ref(fid)
        fn_node = self._resolve_ref(fn_fid, fn_guid)
        if fn_node:
            fn_name = fn_node.get("name") or fn_fid[:8]
            print(f"{pad}CALL → {fn_name}() {label}")
        elif fn_fid:
            print(f"{pad}CALL → (external subflow, guid={fn_guid[:8]}) {label}")
        else:
            print(f"{pad}CALL → ??? {label}")
        self._print_node(self._next(fid), indent)

    def _print_emitter_node2(self, fid, node, indent, pad, label):
        # "Thread Caller" step: fires Controller.StartEventThread(threadNode) and moves on
        # immediately — the thread runs concurrently, it does not block this chain.
        thread_fid, thread_guid = self._thread_ref(fid)
        thread_node = self._resolve_ref(thread_fid, thread_guid)
        if thread_node:
            thread_name = thread_node.get("name") or thread_fid[:8]
        elif thread_fid:
            thread_name = f"(external thread, guid={thread_guid[:8]})"
        else:
            thread_name = "???"
        print(f"{pad}START THREAD \"{thread_name}\" (async, does not block) {label}")
        self._print_node(self._next(fid), indent)

    def _print_timer_node(self, fid, node, indent, pad, label):
        body = node["body"]
        min_v = _field(body, "minValue")
        max_v = _field(body, "maxValue")
        scope = SCOPE_LABEL.get(_field(body, "scope"), _field(body, "scope"))
        field = _field(body, "timerField")
        direction = _field(body, "direction")
        dir_str = "counts down" if direction == "1" else "counts up"
        print(f"{pad}TIMER {label}{scope}.{field} {dir_str} {min_v}..{max_v} (blocks until reached)")
        self._print_node(self._next(fid), indent)

    def _print_math_expression(self, fid, node, indent, pad, label):
        body = node["body"]
        expr = _field(body, "expressionEval") or "?"
        # variables 0, variables 1, ... bind to A/B/C.../V1/V2/... in expressionEval
        var_ids = _port_list(self.nodes, fid, "variables")
        var_descs = []
        for i, vfid in enumerate(var_ids):
            letter = chr(ord('A') + i)
            vn = self.nodes.get(vfid, {})
            var_descs.append(f"{letter}={vn.get('name') or vfid[:8]}")
        vars_str = f" [{', '.join(var_descs)}]" if var_descs else ""
        print(f"{pad}MATH {label}{expr}{vars_str} -> output")
        self._print_node(self._next(fid), indent)

    def _print_switch(self, fid, node, indent, pad, label):
        body = node["body"]
        input_fid = _port(self.nodes, fid, "input")
        input_node = self.nodes.get(input_fid, {})
        input_desc = input_node.get("name") or (input_fid[:8] if input_fid else "?")
        conditions = _yaml_list(body, "conditions")
        print(f"{pad}SWITCH {label}on {input_desc}:")
        for i, cond_value in enumerate(conditions):
            case_fid = _port(self.nodes, fid, f"conditions {i}")
            print(f"{pad}  [\"{cond_value}\"]")
            if case_fid:
                self._print_node(case_fid, indent + 2)
        default_fid = _port(self.nodes, fid, "Default")
        if default_fid:
            print(f"{pad}  [Default]")
            self._print_node(default_fid, indent + 2)

    def _print_table_state_action(self, fid, node, indent, pad, label):
        body = node["body"]
        table_fid, table_guid = _obj_ref(body, "tableBlock")
        table_node = self._resolve_ref(table_fid, table_guid)
        if table_node:
            table_name = table_node.get("name") or table_fid[:8]
        elif table_fid:
            table_name = f"(external table, guid={table_guid[:8]})"
        else:
            table_name = "???"
        state_name = _field(body, "stateName")
        has_condition = _obj_ref(body, "condition")[0] not in ("", "0")
        has_fail = _field(body, "hasFailState") == "1"
        extra = ""
        if has_condition:
            extra += " [conditional per-player]"
        if has_fail:
            extra += f" [failState={_field(body, 'failStateName')}]"
        print(f"{pad}TABLE_STATE {label}{table_name} -> \"{state_name}\"{extra}")
        self._print_node(self._next(fid), indent)

    def _print_start_node(self, fid, node, indent, pad, label):
        # Handled as an entry point in run(); reaching it mid-traversal (shouldn't normally
        # happen) just passes through.
        self._print_node(self._next(fid), indent)

    def _print_end_node(self, fid, node, indent, pad, label):
        print(f"{pad}END {label}")

    def _print_get_int(self, fid, node, indent, pad, label):
        body = node["body"]
        if _field(body, "isRandom") == "1":
            min_v = _field(body, "minValue")
            max_v = _field(body, "maxValue")
            print(f"{pad}GET_INT {label}random[{min_v}, {max_v}]")
        else:
            print(f"{pad}GET_INT {label}{_field(body, 'number')}")
        self._print_node(self._next(fid), indent)

    def _print_listener_node(self, fid, node, indent, pad, label):
        # "Thread Header": entry point of a named concurrent thread's body. Runs every time
        # the matching EmitterNode2 fires it (often more than once — e.g. restarted per round).
        title = node["name"] or "(thread)"
        print(f"{pad}⚡ THREAD \"{title}\" {{")
        next_id = self._next(fid)
        if next_id:
            self._print_node(next_id, indent + 1)
        print(f"{pad}}}")

    def _print_get_pool(self, fid, node, indent, pad, label):
        pool_name = self._resolve_pool_name(fid)
        out_type = _field(node["body"], "outputType")
        print(f"{pad}GET_POOL {label}→ {pool_name} ({out_type})" if out_type else f"{pad}GET_POOL {label}→ {pool_name}")
        self._print_node(self._next(fid), indent)

    def _print_get_piece(self, fid, node, indent, pad, label):
        body = node["body"]
        pool_name = self._resolve_pool_name(fid)
        rule = _field(body, "piecesRule")
        RULES = {"0": "All", "1": "First", "2": "Last", "3": "Random", "4": "AtIndex", "5": "StartingFromIndex", "6": "ExactCount"}
        rule_str = RULES.get(rule, rule)
        print(f"{pad}GET_PIECE {label}from {pool_name} rule={rule_str}")
        self._print_node(self._next(fid), indent)

    def _print_get_context(self, fid, node, indent, pad, label):
        print(f"{pad}GET_CONTEXT {label}(current context/player)")
        self._print_node(self._next(fid), indent)

    def _print_set_context(self, fid, node, indent, pad, label):
        body = node["body"]
        scope = _field(body, "scope")
        steps = self._steps(fid)
        print(f"{pad}SET_CONTEXT {label}scope={scope}" + (":" if steps else ""))
        for s in steps:
            self._print_node(s, indent + 1)
        self._print_node(self._next(fid), indent)

    def _print_pac(self, fid, node, indent, pad, label):
        body = node["body"]
        action_type = _field(body, "actionType")
        count_type = _field(body, "countType")
        count = _field(body, "actionsCount")
        steps = self._steps(fid)
        TYPE_LABEL = {"0": "Sequential", "1": "AllAtOnce"}
        COUNT_LABEL = {"0": "EachPlayer", "1": "Total"}
        actions = []
        for s in steps:
            if s in self.nodes:
                n2 = self.nodes[s]
                actions.append(n2.get("name") or n2["class"])
        print(f"{pad}PAC {label}[{TYPE_LABEL.get(action_type, action_type)}, {COUNT_LABEL.get(count_type, count_type)}={count}]")
        print(f"{pad}  actions: {', '.join(actions)}")
        # Each step is itself a chain (ActionRpcNode → whatever it does next); the PAC's own
        # "next" port is usually unconnected since control resumes from inside a step's chain,
        # not from the PAC as a whole. Print each step's chain so that chain is visible instead
        # of only the action's name.
        for s in steps:
            self._print_node(s, indent + 1)
        self._print_node(self._next(fid), indent)

    def _print_neutral_context(self, fid, node, indent, pad, label):
        steps = self._steps(fid)
        if steps:
            print(f"{pad}SEQUENCE {label}({len(steps)} steps):")
            for s in steps:
                self._print_node(s, indent + 1)
        self._print_node(self._next(fid), indent)

    def _print_same_context(self, fid, node, indent, pad, label):
        steps = self._steps(fid)
        print(f"{pad}SAME_CONTEXT {label}({len(steps)} steps):")
        for s in steps:
            self._print_node(s, indent + 1)
        self._print_node(self._next(fid), indent)

    def _print_eval_data(self, fid, node, indent, pad, label):
        body = node["body"]
        field = _field(body, "field")
        has_ties = _field(body, "hasTies")
        winner_type = _field(body, "winnerType")
        print(f"{pad}EVAL_DATA {label}field={field} hasTies={has_ties} winnerType={winner_type}")
        self._print_node(self._next(fid), indent)

    def _print_set_list(self, fid, node, indent, pad, label):
        body = node["body"]
        field = _field(body, "field") or _field(body, "listName")
        scope = SCOPE_LABEL.get(_field(body, "scope"), _field(body, "scope"))
        op = _field(body, "operation")
        OP_LABEL = {"0": "Set", "1": "Add", "2": "Remove", "3": "Clear"}
        op_str = OP_LABEL.get(op, op)
        print(f"{pad}LIST {label}{scope}.{field} → {op_str}")
        self._print_node(self._next(fid), indent)

    def _print_get_list(self, fid, node, indent, pad, label):
        body = node["body"]
        field = _field(body, "field") or _field(body, "listName")
        scope = SCOPE_LABEL.get(_field(body, "scope"), _field(body, "scope"))
        print(f"{pad}GET_LIST {label}{scope}.{field}")
        self._print_node(self._next(fid), indent)

    def _print_logic_node(self, fid, node, indent, pad, label):
        cls = node["class"]
        inputs = _port_list(self.nodes, fid, "input")  # "input 0", "input 1", ...
        summaries = [self._summarize_condition(i) for i in inputs]
        op = "&&" if cls == "AndNode" else "||"
        print(f"{pad}LOGIC {label}({f' {op} '.join(summaries)})")
        self._print_node(self._next(fid), indent)

    def _print_counter(self, fid, node, indent, pad, label):
        print(f"{pad}COUNTER {label}(increment)")
        self._print_node(self._next(fid), indent)

    def _print_reset_counter(self, fid, node, indent, pad, label):
        print(f"{pad}RESET_COUNTER {label}")
        self._print_node(self._next(fid), indent)

    def _print_function_header(self, fid, node, indent, pad, label):
        # Should already be handled as entry point in run()
        print(f"{pad}FUNCTION_HEADER {label}(already handled)")
        self._print_node(self._next(fid), indent)

    def _print_invoke_action(self, fid, node, indent, pad, label):
        body = node["body"]
        action = _field(body, "actionName")
        block_fid, block_guid = _obj_ref(body, "visualBlock")
        block_node = self._resolve_ref(block_fid, block_guid)
        if block_node:
            block_name = block_node.get("name") or block_fid[:8]
        elif block_fid:
            block_name = f"(external block, guid={block_guid[:8]})"
        else:
            block_name = "???"
        # "state"/other dynamic parameter ports are typically direction=0 (this node's own
        # input), same class of port as SetDataNode's "value" — _port() now covers both.
        state_fid = _port(self.nodes, fid, "state")
        if state_fid and state_fid in self.nodes:
            src = self.nodes[state_fid]
            state_str = f" state<={src['class']}({src.get('name') or state_fid[:8]})"
        else:
            state_str = ""
        print(f"{pad}INVOKE_ACTION {label}{block_name}.\"{action}\"{state_str}")
        self._print_node(self._next(fid), indent)

    def _print_action_rpc(self, fid, node, indent, pad, label):
        body = node["body"]
        action_name = _field(body, "actionName")
        print(f"{pad}ACTION_RPC {label}\"{action_name}\"")
        self._print_node(self._next(fid), indent)

    def _print_smart_action_rpc(self, fid, node, indent, pad, label):
        title = node.get("name", "") or label
        # Pool is from an outgoing connection but referenced via GetPoolNode
        pool_fid = _port(self.nodes, fid, "pool")
        pool_name = self.nodes.get(pool_fid, {}).get("name", "") if pool_fid else ""
        print(f"{pad}SMART_ACTION_RPC {title} pool={pool_name}")
        self._print_node(self._next(fid), indent)

    def _print_context_condition(self, fid, node, indent, pad, label):
        body = node["body"]
        field = _field(body, "field")
        value = _field(body, "value")
        scope = SCOPE_LABEL.get(_field(body, "scope"), _field(body, "scope"))
        print(f"{pad}CONTEXT_COND {label}{scope}.{field} == {value}")
        self._print_node(self._next(fid), indent)

    def _print_subflow_box(self, fid, node, indent, pad, label):
        body = node["body"]
        subflow_title = _field(body, "subFlowTitle") or _field(body, "title") or node["name"]
        print(f"{pad}CALL_SUBFLOW {label}\"{subflow_title}\" (YAML — migrate to C#)")
        self._print_node(self._next(fid), indent)

    def _print_visual_skip(self, fid, node, indent, pad, label):
        cls = node["class"]
        name = node.get("name", "")
        print(f"{pad}# [visual only] {cls} {label}{name}")
        self._print_node(self._next(fid), indent)

    # ── Condition summarizer ─────────────────────────────────────────────────

    def _summarize_condition(self, fid: str) -> str:
        if not fid or fid not in self.nodes:
            return "???"
        node = self.nodes[fid]
        cls = node["class"]
        body = node["body"]
        if cls == "ConditionEvalNode":
            field = _field(body, "field") or _field(body, "customField")
            op = _field(body, "operation")
            value = _field(body, "value")
            scope = CONTEXT_FIELD_SCOPE_LABEL.get(_field(body, "scope"), _field(body, "scope"))
            # Comparator enum (Comparator.cs): more_equal, more, equal, less, less_equal, not_equal
            OPS = {"0": ">=", "1": ">", "2": "==", "3": "<", "4": "<=", "5": "!="}
            return f"{scope}.{field} {OPS.get(op, op)} {value}"
        if cls == "ConditionExpressionNode":
            expr = _field(body, "expressionEval") or _field(body, "expression")
            if expr:
                # replace A/B/C placeholders with variable labels where available
                labels_m = re.findall(r'[A-Z] \| ([^\n]+)', body)
                for i, alias in enumerate(labels_m):
                    letter = chr(ord('A') + i)
                    field_part = alias.split('|')[0].strip() if '|' in alias else alias.strip()
                    expr = expr.replace(letter, field_part)
                return expr
            return "(expression)"
        if cls == "GetBoolNode":
            field = _field(body, "field") or _field(body, "m_FieldName")
            scope = SCOPE_LABEL.get(_field(body, "scope"), _field(body, "scope"))
            return f"{scope}.{field}"
        if cls in ("AndNode", "OrNode"):
            inputs = _port_list(self.nodes, fid, "input")
            parts = [self._summarize_condition(i) for i in inputs]
            op = "&&" if cls == "AndNode" else "||"
            return f"({f' {op} '.join(parts)})"
        if cls == "ContextCondtion":  # typo is real class name
            # ContextCondtion wraps another condition node — follow its own condition port
            inner_fid = _port(self.nodes, fid, "condition")
            if inner_fid:
                return self._summarize_condition(inner_fid)
            return f"{cls}#{fid[:8]}"
        return f"{cls}#{fid[:8]}"


# ─────────────────────────────────────────────────────────────────────────────
#  CLI
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Convert a CodeFlow .asset file to human-readable pseudocode."
    )
    parser.add_argument("asset", help="Path to the .asset file to parse")
    parser.add_argument("-v", "--verbose", action="store_true", help="Show raw field dump per node")
    args = parser.parse_args()

    if not os.path.isfile(args.asset):
        print(f"ERROR: file not found: {args.asset}", file=sys.stderr)
        sys.exit(1)

    nodes = load_flow_nodes(args.asset)
    own_guid = ""
    meta_path = args.asset + ".meta"
    if os.path.isfile(meta_path):
        with open(meta_path, encoding="utf-8") as f:
            m = re.search(r"^guid:\s*([0-9a-f]+)", f.read(), re.MULTILINE)
            if m:
                own_guid = m.group(1)
    printer = Printer(nodes, verbose=args.verbose, own_guid=own_guid)
    printer.run(os.path.basename(args.asset))


if __name__ == "__main__":
    main()
