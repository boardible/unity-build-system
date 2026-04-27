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
    "ad3dd9c150b7b443ba20ddf67a5506ce": "NeutralContext",
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


def _extract_fields(body: str) -> dict:
    """Collect all top-level scalar fields from a MonoBehaviour body."""
    result = {}
    for m in re.finditer(r"^\s{2}(\w+):\s+([^\n{}\[\]]+)$", body, re.MULTILINE):
        result[m.group(1)] = m.group(2).strip()
    return result


def _parse_outgoing_ports(body: str) -> dict:
    """
    Parse the ports.values section and return all OUTGOING port connections.

    Unity xNode stores ports as a parallel keys/values structure.
    _direction: 1 = outgoing (sends data/flow to another node).
    _direction: 0 = incoming (data comes from another node).

    Returns: {port_name: [fileID, ...]}
    Only direction=1 ports with non-zero fileIDs are included.
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
        direction_m = re.search(r"_direction:\s+(\d+)", entry)
        if not fname_m or not direction_m:
            continue
        field_name = fname_m.group(1).strip()
        direction = int(direction_m.group(1))

        if direction != 1:
            continue  # Skip incoming ports — only process outgoing

        # Extract all connected node fileIDs (signed 64-bit ints)
        node_ids = [m.group(1) for m in re.finditer(r"node:\s*\{fileID:\s*(-?\d+)", entry)]
        node_ids = [n for n in node_ids if n != "0"]
        if node_ids:
            result[field_name] = node_ids

    return result


def _port(nodes: dict, file_id: str, port_name: str) -> str:
    """Return the first outgoing fileID for the given port, or ''."""
    outgoing = nodes.get(file_id, {}).get("outgoing", {})
    ids = outgoing.get(port_name, [])
    return ids[0] if ids else ""


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


# ─────────────────────────────────────────────────────────────────────────────
#  Pseudocode printer
# ─────────────────────────────────────────────────────────────────────────────
SKIP_CLASSES = {"ShowReactionNode", "ShowAnimatedBanner", "ShowAnimation", "GetImageNode"}
DISPLAY_ONLY = {"GetImageNode", "ShowReactionNode", "ShowAnimatedBanner", "ShowAnimation"}


class Printer:
    def __init__(self, nodes: dict, verbose: bool = False):
        self.nodes = nodes
        self.verbose = verbose
        self.visited = set()
        # Build index by class for quick lookup
        self._by_class = defaultdict(list)
        for fid, n in nodes.items():
            self._by_class[n["class"]].append(fid)

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

    def _fn_ref(self, fid: str) -> str:
        # FunctionCallerNode calls the function connected on port "function"
        return _port(self.nodes, fid, "function")

    # ── Entry point ──────────────────────────────────────────────────────────

    def run(self, asset_name: str):
        print(f"\n{'='*70}")
        print(f"  {asset_name}")
        print(f"{'='*70}\n")

        # Print each function (FunctionHeaderNode) in document order
        headers = [(fid, n) for fid, n in self.nodes.items() if n["class"] == "FunctionHeaderNode"]
        if not headers:
            # Fall back: find NeutralContext as the root
            roots = [(fid, n) for fid, n in self.nodes.items() if n["class"] in ("NeutralContext", "SameContext")]
            for fid, node in roots:
                self._print_node(fid, indent=0)
            return

        for fid, node in headers:
            self.visited.clear()
            title = node["name"] or "(unnamed function)"
            print(f"┌── FUNCTION: {title}")
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
        }

        handler = dispatch.get(cls)
        if handler:
            handler(fid, node, indent, pad, label)
        else:
            print(f"{pad}??? {label}{cls} #{fid[:10]}")
            self._print_node(self._next(fid), indent)

    # ── Node printers ────────────────────────────────────────────────────────

    def _print_set_data(self, fid, node, indent, pad, label):
        body = node["body"]
        field = _field(body, "field")
        value = _field(body, "value")
        scope = SCOPE_LABEL.get(_field(body, "scope"), _field(body, "scope"))
        # Check if value comes from a connected node (dynamic value)
        src_fid = _port(self.nodes, fid, "value")
        if src_fid and src_fid in self.nodes:
            src = self.nodes[src_fid]
            value = f"<= {src['class']}({src['name'] or src_fid[:8]})"
        print(f"{pad}SET {label}{scope}.{field} = {value}")
        self._print_node(self._next(fid), indent)

    def _print_get_data(self, fid, node, indent, pad, label):
        body = node["body"]
        field = _field(body, "field") or _field(body, "m_FieldName")
        scope = SCOPE_LABEL.get(_field(body, "scope"), _field(body, "scope"))
        print(f"{pad}GET {label}{scope}.{field}")
        self._print_node(self._next(fid), indent)

    def _print_piece_action(self, fid, node, indent, pad, label):
        body = node["body"]
        # PieceActionNode uses 'actionName' (string) not integer actionType
        action_name = _field(body, "actionName") or "?"

        # Pool comes from a GetPoolNode connected to pieceOrPool port
        pool_fid = _port(self.nodes, fid, "pieceOrPool")
        pool_name = self.nodes.get(pool_fid, {}).get("name", "pool") if pool_fid else "pool"

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
            dst_fid = _port(self.nodes, fid, "newPool")
            dst_name = self.nodes.get(dst_fid, {}).get("name", "") if dst_fid else ""
            if dst_name:
                print(f"{pad}PIECE {label}{pool_name}.{action_name} → {dst_name}")
            else:
                print(f"{pad}PIECE {label}{pool_name}.{action_name}")

        self._print_node(self._next(fid), indent)

    def _print_pool_action(self, fid, node, indent, pad, label):
        body = node["body"]
        action_type = _field(body, "actionType")
        pool_fid = _port(self.nodes, fid, "pool")
        if not pool_fid:
            pool_fid = _port(self.nodes, fid, "pieceOrPool")
        pool_name = self.nodes.get(pool_fid, {}).get("name", "pool") if pool_fid else "pool"
        dst_fid = _port(self.nodes, fid, "newPool")
        dst_name = self.nodes.get(dst_fid, {}).get("name", "") if dst_fid else ""
        n = _field(body, "piecesCount")
        POOL_ACTIONS = {"0": "Shuffle", "1": "SendNPieces", "2": "SendAll", "3": "Clear"}
        action_name = POOL_ACTIONS.get(action_type, f"action{action_type}")
        if dst_name:
            print(f"{pad}POOL {label}{pool_name}.{action_name}(n={n}) → {dst_name}")
        else:
            print(f"{pad}POOL {label}{pool_name}.{action_name}(n={n})")
        self._print_node(self._next(fid), indent)

    def _print_each_player(self, fid, node, indent, pad, label):
        body = node["body"]
        list_name = _field(body, "listField") or "kOrder"
        steps = self._steps(fid)
        print(f"{pad}FOREACH player IN {list_name}: {label}")
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
        cond_str = self._summarize_condition(cond_fid)
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
        field = _field(body, "field")
        op = _field(body, "condition")
        value = _field(body, "value")
        scope = SCOPE_LABEL.get(_field(body, "scope"), _field(body, "scope"))
        OPS = {"0": "==", "1": "!=", "2": ">", "3": "<", "4": ">=", "5": "<="}
        op_str = OPS.get(op, op)
        print(f"{pad}COND {label}{scope}.{field} {op_str} {value}")
        self._print_node(self._next(fid), indent)

    def _print_condition_expression(self, fid, node, indent, pad, label):
        body = node["body"]
        expression = _field(body, "expression") or "..."
        print(f"{pad}COND_EXPR {label}{expression}")
        self._print_node(self._next(fid), indent)

    def _print_function_caller(self, fid, node, indent, pad, label):
        fn_fid = self._fn_ref(fid)
        fn_name = self.nodes.get(fn_fid, {}).get("name", fn_fid[:8] if fn_fid else "???") if fn_fid else "???"
        print(f"{pad}CALL → {fn_name}() {label}")
        self._print_node(self._next(fid), indent)

    def _print_get_pool(self, fid, node, indent, pad, label):
        name = node["name"] or "GetPoolNode"
        print(f"{pad}GET_POOL {label}→ {name}")
        self._print_node(self._next(fid), indent)

    def _print_get_piece(self, fid, node, indent, pad, label):
        body = node["body"]
        pool_fid = _port(self.nodes, fid, "pool")
        if not pool_fid:
            pool_fid = _port(self.nodes, fid, "pieceOrPool")
        pool_name = self.nodes.get(pool_fid, {}).get("name", "pool") if pool_fid else "pool"
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
        print(f"{pad}SET_CONTEXT {label}scope={scope}")
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
        print(f"{pad}INVOKE_ACTION {label}\"{action}\"")
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
            op = _field(body, "operation") or _field(body, "condition")
            value = _field(body, "value")
            scope = SCOPE_LABEL.get(_field(body, "scope"), _field(body, "scope"))
            OPS = {"0": "==", "1": "!=", "2": "==", "3": "!=", "4": ">", "5": ">=", "6": "<", "7": "<="}
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

    nodes = parse_asset(args.asset)
    printer = Printer(nodes, verbose=args.verbose)
    printer.run(os.path.basename(args.asset))


if __name__ == "__main__":
    main()
