#!/usr/bin/env python3
"""Turn Unity's NUnit EditMode XML into a summary a human (or an agent) should read instead of the raw
XML, mirroring how smoke runs already publish Logs/smoke-summary-latest.txt.

Exits non-zero when any test failed, so the profile can gate on it.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET

# The asset-integrity tests deliberately report every offending asset, which can run to hundreds of
# lines. Keep the console readable and leave the full text in the XML/text artifact.
MAX_DETAIL_LINES = 40


def parse(results_path: str):
    if not os.path.isfile(results_path):
        return None
    try:
        root = ET.parse(results_path).getroot()
    except ET.ParseError as exc:
        return {"error": f"results XML is malformed: {exc}"}

    cases = []
    for case in root.iter("test-case"):
        result = case.get("result", "")
        entry = {
            "name": case.get("fullname") or case.get("name") or "<unnamed>",
            "result": result,
            "duration": case.get("duration", ""),
        }
        if result not in ("Passed", "Inconclusive"):
            message = case.findtext("./failure/message") or case.findtext("./reason/message") or ""
            entry["message"] = message.strip()
            entry["stack"] = (case.findtext("./failure/stack-trace") or "").strip()
        cases.append(entry)

    return {
        "total": int(root.get("total") or len(cases)),
        "passed": int(root.get("passed") or sum(1 for c in cases if c["result"] == "Passed")),
        "failed": int(root.get("failed") or sum(1 for c in cases if c["result"] == "Failed")),
        "skipped": int(root.get("skipped") or 0),
        "cases": cases,
    }


def render(parsed, run_id: str, exit_code: int, results_path: str, log_path: str) -> tuple[str, int]:
    lines = [f"EditMode tests — run {run_id}"]

    if parsed is None:
        lines += [
            "",
            "VERDICT: NO RESULTS",
            f"Unity exited {exit_code} without writing {results_path}.",
            "That usually means it failed before the test runner started — check the log for",
            "compile errors in the test assemblies (they only build under UNITY_INCLUDE_TESTS).",
            f"log: {log_path}",
        ]
        return "\n".join(lines) + "\n", (exit_code or 1)

    if "error" in parsed:
        lines += ["", "VERDICT: UNREADABLE RESULTS", parsed["error"], f"log: {log_path}"]
        return "\n".join(lines) + "\n", 1

    failures = [c for c in parsed["cases"] if c["result"] == "Failed"]
    verdict = "PASSED" if not failures else "FAILED"
    lines += [
        "",
        f"VERDICT: {verdict}",
        f"total={parsed['total']} passed={parsed['passed']} failed={parsed['failed']} skipped={parsed['skipped']}",
    ]

    for case in failures:
        lines += ["", f"FAILED: {case['name']}"]
        detail = [ln for ln in (case.get("message") or "").splitlines() if ln.strip()]
        shown = detail[:MAX_DETAIL_LINES]
        lines += [f"    {ln}" for ln in shown]
        if len(detail) > len(shown):
            lines.append(f"    ... {len(detail) - len(shown)} more line(s) — see {results_path}")

    lines += ["", f"results: {results_path}", f"log: {log_path}"]
    return "\n".join(lines) + "\n", (1 if failures else 0)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--exit-code", type=int, required=True)
    ap.add_argument("--results", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--json", required=True)
    ap.add_argument("--text", required=True)
    args = ap.parse_args()

    parsed = parse(args.results)
    text, status = render(parsed, args.run_id, args.exit_code, args.results, args.log)

    payload = {
        "schemaVersion": 1,
        "runId": args.run_id,
        "profile": "tests",
        "status": "passed" if status == 0 else "failed",
        "exitCode": args.exit_code,
        "summary": None if parsed is None or "error" in parsed else {
            k: parsed[k] for k in ("total", "passed", "failed", "skipped")
        },
        "failed": [] if parsed is None or "error" in parsed else [
            {"name": c["name"], "message": c.get("message", "")}
            for c in parsed["cases"] if c["result"] == "Failed"
        ],
        "artifacts": {"results": args.results, "log": args.log, "text": args.text},
    }

    os.makedirs(os.path.dirname(args.json) or ".", exist_ok=True)
    with open(args.json, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, indent=2) + "\n")
    with open(args.text, "w", encoding="utf-8") as handle:
        handle.write(text)

    # Stable path so the latest verdict is findable without knowing the run id, matching the
    # smoke-summary-latest.txt convention.
    logs_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(args.json))), "..")
    latest = os.path.normpath(os.path.join(logs_dir, "edit-tests-summary-latest.txt"))
    try:
        with open(latest, "w", encoding="utf-8") as handle:
            handle.write(text)
    except OSError:
        pass

    sys.stdout.write(text)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
