#!/usr/bin/env python3
"""Token-progressive gameplay debugging for live Editor sessions and saved runs."""

import argparse
import json
import re
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

from unity_control_bridge import find_workspace_root, resolve_project_path, send_request


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def emit(payload: object, pretty: bool) -> None:
    print(json.dumps(payload, indent=2 if pretty else None, separators=None if pretty else (",", ":"), ensure_ascii=False))


def resolve_run(project: Path, run_arg: str) -> Path:
    runs_root = project / "Logs" / "runs"
    if run_arg != "latest":
        path = Path(run_arg)
        if not path.is_absolute():
            path = runs_root / run_arg
        if path.is_dir():
            return path.resolve()
        raise SystemExit(f"Run not found: {path}")
    runs = [path for path in runs_root.iterdir() if path.is_dir()] if runs_root.is_dir() else []
    if not runs:
        raise SystemExit(f"No runs found under {runs_root}")
    return max(runs, key=lambda path: path.stat().st_mtime).resolve()


def compact_event(event: dict) -> dict:
    details = event.get("details") or {}
    compact = {
        "seq": event.get("sequence"),
        "t": event.get("realtimeSeconds"),
        "kind": f"{event.get('category')}.{event.get('name')}",
    }
    if event.get("threadId"):
        compact["thread"] = event["threadId"]
    for key in ("status", "node", "from", "to", "actionId", "playerId", "scope", "field", "ownerId", "handled"):
        if details.get(key) is not None:
            compact[key] = details[key]
    return compact


def compact_diagnostics(value: object) -> dict:
    if not isinstance(value, str):
        return {}
    fields = {}
    for item in re.split(r"(?:;|,) (?=[A-Za-z][A-Za-z0-9]*=)", value):
        key, separator, field_value = item.partition("=")
        if separator:
            fields[key] = field_value
    keep = (
        "stage", "state", "roomState", "controllerGameRunning",
        "controllerThreadStatus", "controllerThreadNode", "controllerThreadPac",
        "controllerThreadPacAllowedPlayers", "controllerThreadPacWaitingActions",
        "currentTurnPlayers", "rpcHistoryCount", "rpcQueueCount",
        "localPlayerIsBot", "players", "showedResults",
    )
    return {key: fields[key] for key in keep if fields.get(key) not in (None, "null", "none", "")}


def parse_utc(value: object) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def diagnose_timeline(events: list[dict], gameplay: dict, finished_at: object) -> list[dict]:
    diagnoses = []
    if not events:
        return [{"code": "no-history", "severity": "warning", "summary": "No gameplay journal events were captured."}]

    last_realtime = float(events[-1].get("realtimeSeconds") or 0)
    recent = [event for event in events if last_realtime - float(event.get("realtimeSeconds") or 0) <= 3]
    recent_steps = sum(event.get("category") == "thread" and event.get("name") == "step" for event in recent)
    last_utc = parse_utc(events[-1].get("timestampUtc"))
    finished_utc = parse_utc(finished_at)
    capture_lag = (finished_utc - last_utc).total_seconds() if last_utc and finished_utc else None
    if len(recent) >= 20 and recent_steps >= 5 and (capture_lag is None or capture_lag <= 3):
        diagnoses.append({
            "code": "active-at-timeout",
            "severity": "info",
            "summary": "Engine was still making progress at capture time; treat this as a timeout before a deadlock.",
            "evidence": {"eventsLast3s": len(recent), "threadStepsLast3s": recent_steps},
        })

    waiting_rpc = str(gameplay.get("CurrentThreadStatus", "")) == "WaitingRpc"
    waiting_actions = gameplay.get("WaitingActions") or []
    rpc_queue = int(gameplay.get("RpcQueueCount") or 0)
    recent_rpcs = [event for event in events if event.get("category") == "rpc" and last_realtime - float(event.get("realtimeSeconds") or 0) <= 5]
    if waiting_rpc and waiting_actions and rpc_queue == 0 and not recent_rpcs:
        diagnoses.append({
            "code": "rpc-producer-missing",
            "severity": "warning",
            "summary": "Current thread awaits an action, but no RPC is queued or recently observed.",
            "evidence": {"node": gameplay.get("CurrentThreadNode"), "waitingActions": waiting_actions[:4]},
        })

    unhandled = [event for event in events if event.get("category") == "rpc" and event.get("name") == "unhandled"]
    if unhandled:
        actions = Counter((event.get("details") or {}).get("actionId") for event in unhandled)
        diagnoses.append({
            "code": "unhandled-rpc",
            "severity": "error",
            "summary": "Gameplay RPCs were not handled.",
            "evidence": {"count": len(unhandled), "actions": dict(actions.most_common(4))},
        })

    exceptions = [event for event in events if event.get("name") == "exception"]
    if exceptions:
        diagnoses.append({
            "code": "thread-exception",
            "severity": "error",
            "summary": "Gameplay thread exceptions were recorded.",
            "evidence": {"count": len(exceptions), "last": compact_event(exceptions[-1])},
        })

    transitions: dict[tuple[object, object, object], list[object]] = {}
    for event in events:
        if event.get("category") != "data" or event.get("name") != "changed":
            continue
        details = event.get("details") or {}
        key = (details.get("scope"), details.get("ownerId"), details.get("field"))
        transitions.setdefault(key, []).append(details.get("to"))
    oscillating = []
    for (scope, owner, field), values in transitions.items():
        tail = values[-8:]
        if len(tail) >= 6 and len(set(tail)) == 2 and all(tail[index] != tail[index - 1] for index in range(1, len(tail))):
            oscillating.append({"scope": scope, "ownerId": owner, "field": field, "changes": len(values)})
    if oscillating:
        diagnoses.append({
            "code": "state-oscillation",
            "severity": "warning",
            "summary": "Data fields repeatedly alternate between two values.",
            "evidence": oscillating[:4],
        })
    return diagnoses


def timeline_digest(path: Path, gameplay_path: Path | None = None, finished_at: object = None) -> dict:
    timeline = read_json(path)
    events = timeline.get("events", [])
    gameplay = read_json(gameplay_path) if gameplay_path and gameplay_path.is_file() else {}
    category_counts = Counter(event.get("category", "unknown") for event in events)
    waits = [event for event in events if event.get("category") == "thread" and event.get("name") == "waiting"]
    rpcs = [event for event in events if event.get("category") == "rpc"]
    changes = [event for event in events if event.get("category") == "data"]
    return {
        "path": str(path),
        "cursor": timeline.get("cursor"),
        "eventCount": len(events),
        "categories": dict(category_counts),
        "latestWaits": [compact_event(event) for event in waits[-5:]],
        "latestRpcs": [compact_event(event) for event in rpcs[-8:]],
        "latestDataChanges": [compact_event(event) for event in changes[-5:]],
        "tail": [compact_event(event) for event in events[-8:]],
        "diagnoses": diagnose_timeline(events, gameplay, finished_at),
    }


def inspect_run(run_root: Path) -> dict:
    summary_path = run_root / "summary.json"
    if not summary_path.exists():
        raise SystemExit(f"Summary not found: {summary_path}")
    summary = read_json(summary_path)
    failures = []
    timeline_inputs = []
    for game in summary.get("games", []):
        for phase in game.get("phases", []):
            if phase.get("status") == "passed":
                continue
            artifacts = phase.get("artifacts") or {}
            failure = {
                "gameId": game.get("gameId"),
                "phase": phase.get("phase"),
                "fingerprint": phase.get("fingerprint"),
                "durationSeconds": phase.get("durationSeconds"),
                "message": phase.get("message"),
                "state": compact_diagnostics(phase.get("diagnostics")),
                "artifacts": artifacts,
            }
            failures.append(failure)
            if artifacts.get("timeline"):
                gameplay_path = Path(artifacts["gameplay"]) if artifacts.get("gameplay") else None
                timeline_inputs.append((Path(artifacts["timeline"]), gameplay_path, phase.get("finishedAtUtc")))
    return {
        "runId": summary.get("runId"),
        "status": summary.get("status"),
        "counts": summary.get("counts"),
        "failures": failures,
        "timelines": [timeline_digest(path, gameplay, finished) for path, gameplay, finished in timeline_inputs if path.is_file()],
        "nextActions": [
            "Read diagnostics/gameplay for the failed game and phase.",
            "Use the timeline cursor and category filters before opening unity.log.",
            "Use dev-check.sh triage <game> for a reliable visual capture in an open Editor.",
        ] if failures else [],
    }


def flatten(value: object, prefix: str = "") -> dict[str, object]:
    result = {}
    if isinstance(value, dict):
        for key, child in value.items():
            result.update(flatten(child, f"{prefix}.{key}" if prefix else str(key)))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            result.update(flatten(child, f"{prefix}[{index}]"))
    else:
        result[prefix] = value
    return result


def diff_snapshots(before_path: Path, after_path: Path, limit: int) -> dict:
    before = flatten(read_json(before_path))
    after = flatten(read_json(after_path))
    changes = []
    for key in sorted(set(before) | set(after)):
        if before.get(key) != after.get(key):
            changes.append({"path": key, "from": before.get(key), "to": after.get(key)})
    return {"changed": len(changes), "truncated": len(changes) > limit, "changes": changes[:limit]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".")
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--pretty", action="store_true", help="Pretty JSON; compact is the token-saving default")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("overview")
    commands.add_parser("definition")
    timeline = commands.add_parser("timeline")
    timeline.add_argument("--since", type=int, default=0)
    timeline.add_argument("--limit", type=int, default=50)
    timeline.add_argument("--categories", default=None)
    timeline.add_argument("--match", default=None)
    logs = commands.add_parser("logs")
    logs.add_argument("--since", type=int, default=0)
    logs.add_argument("--limit", type=int, default=30)
    logs.add_argument("--types", default=None)
    logs.add_argument("--contains", default=None)
    logs.add_argument("--stack", action="store_true")
    trace = commands.add_parser("trace")
    trace.add_argument("selectors")
    trace.add_argument("--phases", default="Execute,GetNextStep")
    trace.add_argument("--disable", action="store_true")
    inspect = commands.add_parser("inspect-run")
    inspect.add_argument("run", nargs="?", default="latest")
    fingerprints = commands.add_parser("fingerprints")
    fingerprints.add_argument("fingerprint", nargs="?", default=None)
    diff = commands.add_parser("diff")
    diff.add_argument("before")
    diff.add_argument("after")
    diff.add_argument("--limit", type=int, default=100)
    args = parser.parse_args()

    workspace = find_workspace_root(Path(__file__))
    project = resolve_project_path(args.project, workspace)
    if args.command == "overview":
        payload = send_request(project, "get_gameplay_overview", {}, args.timeout)["result"]
    elif args.command == "definition":
        payload = send_request(project, "get_game_definition", {}, args.timeout)["result"]
    elif args.command == "timeline":
        request = {"since": args.since, "limit": args.limit}
        if args.categories:
            request["categories"] = args.categories
        if args.match:
            request["match"] = args.match
        payload = send_request(project, "get_gameplay_timeline", request, args.timeout)["result"]
    elif args.command == "logs":
        request = {"since": args.since, "limit": args.limit, "includeStackTrace": args.stack}
        if args.types:
            request["types"] = args.types
        if args.contains:
            request["contains"] = args.contains
        payload = send_request(project, "get_recent_logs", request, args.timeout)["result"]
    elif args.command == "trace":
        payload = send_request(project, "configure_gameplay_trace", {
            "selectors": args.selectors,
            "phases": args.phases,
            "enabled": not args.disable,
        }, args.timeout)["result"]
    elif args.command == "inspect-run":
        payload = inspect_run(resolve_run(project, args.run))
    elif args.command == "fingerprints":
        index_path = project / "Logs" / "smoke-fingerprint-index.json"
        index = read_json(index_path) if index_path.exists() else {"schemaVersion": 1, "fingerprints": {}}
        payload = index.get("fingerprints", {}).get(args.fingerprint) if args.fingerprint else index
    else:
        payload = diff_snapshots(Path(args.before), Path(args.after), args.limit)
    emit(payload, args.pretty)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except TimeoutError as exc:
        print(json.dumps({
            "error": "bridge-timeout",
            "message": str(exc),
            "next": "Open the Unity Editor for this project, then retry the same command.",
        }, separators=(",", ":")), file=sys.stderr)
        raise SystemExit(2)
