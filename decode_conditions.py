#!/usr/bin/env python3
"""Resolve every ConditionExpressionNode in a legacy FlowGraph asset to a readable expression.

`parse_flow.py` prints branch conditions as `A == C and B == D` because it only reads
`expressionEval` and gives up on the operands. The operands are not lost: each variable
slot is a `DataReference` stored under the node's `references: RefIds:` block, and the
constants keep their .NET BinaryFormatter payload in `valueByte`. That payload is plain
enough to recover the literal (enum name, string, int, bool) with a small reader.

That difference decides real behaviour. In Allumbra the port had guessed at the cancel
and cost rules; the graph actually says `prevCard != Reload` gates the ammo charge — a
whole "your next card is free after a Reload" mechanic that no amount of staring at
`A ~= B` would have revealed.

Variable slots resolve to one of:
  Source     -> `<scope>.<fieldName>`      (scope 3 = current player context)
  Constant   -> the decoded literal, or `<flow:...>` when the graph feeds it at runtime
  connected  -> `<-nodeTitle.port` when the slot is wired to another node's output

Usage:
    python3 Scripts/decode_conditions.py <flow.asset>
    python3 Scripts/decode_conditions.py <flow.asset> --node IfNode#3
"""

from __future__ import annotations

import argparse
import binascii
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import parse_flow as pf  # noqa: E402

# DataReference_Source.source is a SourceScope enum; only the values that actually
# appear in the shipped graphs are named here. Anything else prints its raw number.
SOURCE_SCOPE = {
    "0": "neutral", "1": "team", "2": "global", "3": "player",
    "4": "piece", "5": "pool", "6": "context",
}


def decode_constant(hex_blob: str):
    """Recover the literal from a BinaryFormatter payload."""
    if not hex_blob:
        return None
    try:
        raw = binascii.unhexlify(hex_blob)
    except binascii.Error:
        return None

    # Boxed primitives serialize the field name then the value.
    match = re.search(rb"m_value\x00\x08(....)", raw)
    if match:
        return struct.unpack("<i", match.group(1))[0]
    match = re.search(rb"m_value\x00\x01(.)", raw)
    if match:
        return bool(match.group(1)[0])
    match = re.search(rb"m_value\x00\x0b(........)", raw)
    if match:
        return struct.unpack("<d", match.group(1))[0]

    # Bare strings (enum members, localization keys) are length-prefixed at the tail.
    strings = [s.decode() for s in re.findall(rb"[\x20-\x7e]{2,}", raw)]
    strings = [s for s in strings if not s.startswith("System.") and "Version=" not in s]
    return strings[-1] if strings else None


def _refids(body: str) -> dict:
    """rid -> (class, data-block text) from the node's `references:` section."""
    out = {}
    section = body[body.find("references:"):]
    for match in re.finditer(
        r"- rid: (\d+)\n\s+type: \{class: ([^,]*),[^\n]*\n\s+data:\n((?:\s{8}.*\n?)*)",
        section,
    ):
        out[match.group(1)] = (match.group(2).strip(), match.group(3))
    return out


def _slot_rids(body: str):
    """The `contexts: - rid:` of each `variables:` entry, in declaration order."""
    section = re.search(r"\n  variables:\n(.*?)\n  (?:expressionEval|variableLabels):", body, re.S)
    if not section:
        return []
    return re.findall(r"contexts:\n\s+- rid: (\d+)", section.group(1))


def describe_slot(nodes, fid, index, rid, refids) -> str:
    # A wired slot beats whatever placeholder the reference holds.
    target = pf._port(nodes, fid, f"variables {index}")
    if target and target in nodes:
        title = re.search(r"\n  title: ([^\n]+)", nodes[target]["body"])
        return f"<-{title.group(1).strip() if title else target}"

    klass, data = refids.get(rid, ("", ""))
    if klass == "DataReference_Source":
        field = re.search(r"fieldName: ([^\n]*)", data)
        scope = re.search(r"source: (\d+)", data)
        scope_name = SOURCE_SCOPE.get(scope.group(1) if scope else "", scope.group(1) if scope else "?")
        return f"{scope_name}.{(field.group(1).strip() if field else '?')}"
    if klass == "DataReference_Constant":
        blob = re.search(r"valueByte: ([0-9a-f]*)", data)
        value = decode_constant(blob.group(1) if blob else "")
        if value is None:
            note = re.search(r"overrideDescription: ([^\n]*)", data)
            return f"<{note.group(1).strip() if note else 'constant?'}>"
        return repr(value)
    return f"<{klass or 'unresolved'}>"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("asset")
    parser.add_argument("--node", help="only this IfNode/ConditionExpressionNode title")
    args = parser.parse_args()

    nodes = pf.load_flow_nodes(args.asset)
    titles = {}
    for fid, node in nodes.items():
        match = re.search(r"\n  title: ([^\n]+)", node["body"])
        if match:
            titles[fid] = match.group(1).strip()

    printed = 0
    for fid, node in nodes.items():
        if node["class"] != "ConditionExpressionNode":
            continue
        body = node["body"]
        expression = re.search(r"\n  expressionEval: ([^\n]*)", body)
        if not expression:
            continue

        # Report under the IfNode that owns it — that is the name parse_flow prints.
        owner = ""
        for other_fid in nodes:
            if pf._port(nodes, other_fid, "condition") == fid:
                owner = titles.get(other_fid, "")
                break
        if args.node and args.node not in (owner, titles.get(fid, "")):
            continue

        refids = _refids(body)
        slots = _slot_rids(body)
        resolved = expression.group(1).strip()
        legend = []
        for index, rid in enumerate(slots):
            # Slot names run A..Z; past 26 the graph reuses none, so leave them raw
            # rather than walking off the end of the alphabet into regex metacharacters.
            if index >= 26:
                break
            letter = chr(ord("A") + index)
            text = describe_slot(nodes, fid, index, rid, refids)
            legend.append(f"{letter}={text}")
            # Replacement is literal — decoded values can contain backslashes and \1-style text.
            resolved = re.sub(rf"(?<![\w.]){letter}(?![\w])", lambda _match, t=text: t, resolved)

        print(f"{owner or titles.get(fid, fid)}:  {resolved}")
        print(f"    raw: {expression.group(1).strip()}   [{', '.join(legend)}]")
        printed += 1

    if printed == 0:
        print("no matching ConditionExpressionNode", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
