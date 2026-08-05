#!/usr/bin/env python3
"""Create compact text/JSON smoke summaries and small failure triage bundles."""

import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

MAX_MESSAGE_LINES = 8
MAX_LINE_WIDTH = 240
SIGNAL_LIMIT = 200


def newest(pattern: str) -> str | None:
    matches = glob.glob(pattern)
    return max(matches, key=os.path.getmtime) if matches else None


def clipped_lines(text: str) -> list[str]:
    lines = [line.rstrip()[:MAX_LINE_WIDTH] for line in (text or "").splitlines() if line.strip()]
    result = lines[:MAX_MESSAGE_LINES]
    if len(lines) > MAX_MESSAGE_LINES:
        result.append(f"... (+{len(lines) - MAX_MESSAGE_LINES} more lines)")
    return result


def fingerprint(phase: str, exception_type: str | None, message: str | None) -> str | None:
    if not message and not exception_type:
        return None
    normalized = f"{phase}|{exception_type or ''}|{message or ''}".lower()
    normalized = re.sub(r"0x[0-9a-f]+", "<hex>", normalized)
    normalized = re.sub(r"\b[0-9a-f]{24,}\b", "<id>", normalized)
    normalized = re.sub(r"\b\d+(?:\.\d+)?\b", "<n>", normalized)
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:12]


def read_events(paths: list[str]) -> list[dict]:
    events = []
    for raw_path in paths:
        path = Path(raw_path)
        if not path.exists():
            continue
        with path.open(encoding="utf-8", errors="replace") as handle:
            for line_number, line in enumerate(handle, start=1):
                if not line.strip():
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError as error:
                    events.append({
                        "gameId": "__runner__",
                        "phase": "events",
                        "status": "failed",
                        "message": f"Invalid event JSON at {path.name}:{line_number}: {error}",
                    })
                    continue
                event["eventsPath"] = str(path.resolve())
                events.append(event)
    return events


def parse_xml(paths: list[str]) -> tuple[list[dict], dict]:
    phases = []
    totals = {"total": 0, "passed": 0, "failed": 0, "durationSeconds": 0.0, "parseErrors": []}
    for raw_path in paths:
        path = Path(raw_path)
        if not path.exists():
            continue
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError as error:
            totals["parseErrors"].append(f"{path.name}: {error}")
            continue
        run = root if root.tag == "test-run" else root.find(".//test-run") or root
        for key in ("total", "passed", "failed"):
            try:
                totals[key] += int(run.get(key) or 0)
            except ValueError:
                pass
        try:
            totals["durationSeconds"] += float(run.get("duration") or 0)
        except ValueError:
            pass
        for case in run.iter("test-case"):
            name = case.get("methodname") or case.get("name") or "unknown"
            result = case.get("result") or "Unknown"
            failure = case.find("failure")
            message = failure.findtext("message") if failure is not None else None
            phase_status = "passed" if result == "Passed" else ("skipped" if result == "Skipped" else "failed")
            phases.append({
                "name": name,
                "status": phase_status,
                "durationSeconds": float(case.get("duration") or 0),
                "message": message.strip() if message else None,
                "source": str(path.resolve()),
            })
    return phases, totals


def build_summary(run_id: str, xml_paths: list[str], event_paths: list[str], log_paths: list[str], artifact_root: str | None) -> dict:
    events = read_events(event_paths)
    phases, totals = parse_xml(xml_paths)
    games: dict[str, dict] = {}

    for event in events:
        game_id = event.get("gameId") or "unknown"
        phase = event.get("phase") or "unknown"
        status = event.get("status") or "unknown"
        message = event.get("message")
        entry = {
            "phase": phase,
            "status": status,
            "durationSeconds": float(event.get("durationSeconds") or 0),
            "fingerprint": fingerprint(phase, event.get("exceptionType"), message) if status != "passed" else None,
            "message": message,
            "diagnostics": event.get("diagnostics"),
            "failureCategory": event.get("failureCategory"),
            "failureStage": event.get("failureStage"),
            "gameplayFailure": bool(event.get("gameplayFailure")),
            "multiplayerFailureProven": bool(event.get("multiplayerFailureProven")),
            "artifactCaptureStatus": event.get("artifactCaptureStatus"),
            "artifactCaptureIssues": event.get("artifactCaptureIssues") or [],
            "artifacts": event.get("artifacts") or {},
            "startedAtUtc": event.get("startedAtUtc"),
            "finishedAtUtc": event.get("finishedAtUtc"),
        }
        game = games.setdefault(game_id, {"gameId": game_id, "status": "passed", "durationSeconds": 0.0, "phases": []})
        game["phases"].append(entry)
        game["durationSeconds"] = round(game["durationSeconds"] + entry["durationSeconds"], 3)
        if status != "passed":
            game["status"] = "failed"

    phase_failed = any(phase["status"] == "failed" for phase in phases)
    game_failed = any(game["status"] != "passed" for game in games.values())
    status = "failed" if phase_failed or game_failed or totals["parseErrors"] else "passed"
    if not phases and not events:
        status = "unknown"

    return {
        "schemaVersion": 1,
        "runId": run_id,
        "status": status,
        "durationSeconds": round(totals["durationSeconds"], 3),
        "counts": {
            "games": len([game for game in games if game != "__runner__"]),
            "gamesPassed": sum(1 for game in games.values() if game["status"] == "passed"),
            "gamesFailed": sum(1 for game in games.values() if game["status"] != "passed"),
            "tests": totals["total"],
            "testsPassed": totals["passed"],
            "testsFailed": totals["failed"],
        },
        "games": sorted(games.values(), key=lambda game: game["gameId"].lower()),
        "testPhases": phases,
        "parseErrors": totals["parseErrors"],
        "artifacts": {
            "root": str(Path(artifact_root).resolve()) if artifact_root else None,
            "results": [str(Path(path).resolve()) for path in xml_paths if Path(path).exists()],
            "events": [str(Path(path).resolve()) for path in event_paths if Path(path).exists()],
            "logs": [str(Path(path).resolve()) for path in log_paths if Path(path).exists()],
        },
    }


def render_text(summary: dict) -> str:
    counts = summary["counts"]
    duration = summary["durationSeconds"] / 60 if summary["durationSeconds"] else 0
    lines = [
        f"SMOKE {summary['status'].upper()}  run={summary['runId']}  duration={duration:.1f}min",
        f"games={counts['games']} passed={counts['gamesPassed']} failed={counts['gamesFailed']}  tests={counts['tests']} failed={counts['testsFailed']}",
        "",
    ]
    for game in summary["games"]:
        phase_text = ", ".join(
            f"{phase['phase']}={phase['status']}{'/' + phase['fingerprint'] if phase.get('fingerprint') else ''}"
            for phase in game["phases"]
        )
        lines.append(f"{game['status'].upper():6} {game['gameId']:<18} {game['durationSeconds']:>7.1f}s  {phase_text}")
        for phase in game["phases"]:
            if phase["status"] != "passed":
                if phase.get("failureCategory"):
                    lines.append(
                        "  classification="
                        f"{phase['failureCategory']}@{phase.get('failureStage') or 'unknown'} "
                        f"gameplayFailure={str(phase.get('gameplayFailure', False)).lower()} "
                        f"multiplayerFailureProven={str(phase.get('multiplayerFailureProven', False)).lower()} "
                        f"artifactCapture={phase.get('artifactCaptureStatus') or 'unknown'}"
                    )
                lines.extend(f"  {line}" for line in clipped_lines(phase.get("message") or phase.get("diagnostics") or "unknown failure"))
    if not summary["games"]:
        for phase in summary["testPhases"]:
            lines.append(f"{phase['status'].upper():6} {phase['name']}")
            if phase["status"] != "passed":
                lines.extend(f"  {line}" for line in clipped_lines(phase.get("message") or "unknown failure"))
    else:
        failed_suite_phases = [phase for phase in summary["testPhases"] if phase["status"] == "failed"]
        if failed_suite_phases:
            lines.append("")
            lines.append("FAILED SUITE PHASES")
            for phase in failed_suite_phases:
                lines.append(f"FAILED {phase['name']}")
                lines.extend(f"  {line}" for line in clipped_lines(phase.get("message") or "unknown suite failure"))
    if summary["parseErrors"]:
        lines.append("")
        lines.extend(f"XML ERROR: {error}" for error in summary["parseErrors"])
    return "\n".join(lines).rstrip() + "\n"


def write_triage_bundle(summary: dict, triage_dir: str, log_paths: list[str]) -> None:
    if summary["status"] != "failed":
        return
    root = Path(triage_dir)
    root.mkdir(parents=True, exist_ok=True)
    signal = re.compile(r"(\[SmokeEvent\]|\[Smoke\].*(fail|timeout)|\[Exception\]|Exception:|Assert\.|Expected:|But was:|Exceed Timeout)", re.I)
    hits = []
    for raw_path in log_paths:
        path = Path(raw_path)
        if not path.exists():
            continue
        with path.open(encoding="utf-8", errors="replace") as handle:
            hits.extend(line.rstrip()[:MAX_LINE_WIDTH] for line in handle if signal.search(line))
    (root / "signals.log").write_text("\n".join(hits[-SIGNAL_LIMIT:]) + ("\n" if hits else ""), encoding="utf-8")
    summary_path = root / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    manifest = {
        "runId": summary["runId"],
        "summary": str(summary_path.resolve()),
        "signals": str((root / "signals.log").resolve()),
        "caseArtifacts": [
            phase["artifacts"]
            for game in summary["games"]
            for phase in game["phases"]
            if phase["status"] != "passed" and phase.get("artifacts")
        ],
    }
    (root / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def update_fingerprint_index(summary: dict, index_path: str) -> None:
    path = Path(index_path)
    try:
        index = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"schemaVersion": 1, "fingerprints": {}}
    except (json.JSONDecodeError, OSError):
        index = {"schemaVersion": 1, "fingerprints": {}}
    entries = index.setdefault("fingerprints", {})
    for game in summary.get("games", []):
        for phase in game.get("phases", []):
            key = phase.get("fingerprint")
            if not key:
                continue
            current = entries.setdefault(key, {
                "count": 0,
                "firstSeenUtc": phase.get("finishedAtUtc"),
                "games": [],
                "phases": [],
            })
            current["count"] += 1
            current["lastSeenUtc"] = phase.get("finishedAtUtc")
            current["lastRunId"] = summary.get("runId")
            current["lastMessage"] = phase.get("message")
            current["lastArtifacts"] = phase.get("artifacts") or {}
            current["games"] = sorted(set(current.get("games", [])) | {game.get("gameId")})
            current["phases"] = sorted(set(current.get("phases", [])) | {phase.get("phase")})
    if len(entries) > 200:
        ordered = sorted(entries.items(), key=lambda item: item[1].get("lastSeenUtc") or "", reverse=True)
        index["fingerprints"] = dict(ordered[:200])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xml", nargs="*", help="NUnit result XML(s)")
    parser.add_argument("--events", action="append", default=[], help="Smoke event NDJSON (repeatable)")
    parser.add_argument("--log", action="append", default=[], help="Unity log (repeatable)")
    parser.add_argument("--logs-dir", default=None)
    parser.add_argument("--run-id", default="legacy")
    parser.add_argument("--artifact-root", default=None)
    parser.add_argument("--out", default=None, help="Text summary path")
    parser.add_argument("--json-out", default=None, help="JSON summary path")
    parser.add_argument("--triage-dir", default=None)
    parser.add_argument("--fingerprint-index", default=None, help="Persistent local failure-memory JSON")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)

    project_dir = Path(__file__).resolve().parent.parent
    logs_dir = Path(args.logs_dir) if args.logs_dir else project_dir / "Logs"
    xml_paths = args.xml or ([newest(str(logs_dir / "smoke-playmode-*.xml"))] if newest(str(logs_dir / "smoke-playmode-*.xml")) else [])
    log_paths = args.log or ([newest(str(logs_dir / "unity-smoke-*.log"))] if newest(str(logs_dir / "unity-smoke-*.log")) else [])
    summary = build_summary(args.run_id, xml_paths, args.events, log_paths, args.artifact_root)
    text = render_text(summary)

    out_path = Path(args.out) if args.out else logs_dir / "smoke-summary-latest.txt"
    json_path = Path(args.json_out) if args.json_out else logs_dir / "smoke-summary-latest.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(text, encoding="utf-8")
    json_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    if args.triage_dir:
        write_triage_bundle(summary, args.triage_dir, log_paths)
    if args.fingerprint_index:
        update_fingerprint_index(summary, args.fingerprint_index)
    if not args.quiet:
        sys.stdout.write(text)
        print(f"\n[text: {out_path}]\n[json: {json_path}]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
