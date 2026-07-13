#!/usr/bin/env python3

import argparse
import json
import sys
import time
import uuid
from pathlib import Path


def find_workspace_root(script_path: Path) -> Path:
    for candidate in [script_path.resolve().parent, *script_path.resolve().parents]:
        if (candidate / "CLAUDE.md").exists():
            return candidate
    return script_path.resolve().parents[1]


def resolve_project_path(project_arg: str, workspace_root: Path) -> Path:
    candidate = Path(project_arg)
    if candidate.exists():
        return candidate.resolve()

    nested = workspace_root / project_arg
    if nested.exists():
        return nested.resolve()

    raise SystemExit(f"Project not found: {project_arg}")


def bridge_paths(project_root: Path) -> dict[str, Path]:
    root = project_root / ".utmp" / "unity-control-bridge"
    return {
        "root": root,
        "heartbeat": root / "bridge.json",
        "requests": root / "requests",
        "responses": root / "responses",
        "screenshots": root / "screenshots",
    }


def ensure_dirs(paths: dict[str, Path]) -> None:
    paths["requests"].mkdir(parents=True, exist_ok=True)
    paths["responses"].mkdir(parents=True, exist_ok=True)
    paths["screenshots"].mkdir(parents=True, exist_ok=True)


def prune_files(directory: Path, pattern: str, keep: int) -> None:
    files = sorted(directory.glob(pattern), key=lambda path: path.stat().st_mtime, reverse=True)
    for stale_path in files[keep:]:
        stale_path.unlink(missing_ok=True)


def write_request(request_path: Path, payload: dict) -> None:
    temp_path = request_path.with_suffix(request_path.suffix + ".tmp")
    temp_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    temp_path.replace(request_path)


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def wait_for_response(response_path: Path, timeout_seconds: float) -> dict:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        if response_path.exists():
            return read_json(response_path)
        time.sleep(0.1)
    raise TimeoutError(f"Timed out waiting for {response_path.name}")


def send_request(project_root: Path, command: str, args: dict | None, timeout_seconds: float) -> dict:
    paths = bridge_paths(project_root)
    ensure_dirs(paths)
    prune_files(paths["responses"], "*.json", 20)
    prune_files(paths["screenshots"], "*.png", 10)

    request_id = uuid.uuid4().hex
    request = {
        "id": request_id,
        "command": command,
        "args": args or {},
    }

    request_path = paths["requests"] / f"{request_id}.json"
    response_path = paths["responses"] / f"{request_id}.json"
    if response_path.exists():
        response_path.unlink()

    write_request(request_path, request)
    try:
        return wait_for_response(response_path, timeout_seconds)
    finally:
        # These files belong to this synchronous client invocation. Once read (or
        # timed out), retaining them only creates an ever-growing local queue. A
        # request already claimed by Unity has been renamed and this is a no-op.
        request_path.unlink(missing_ok=True)
        response_path.unlink(missing_ok=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Local Unity control bridge client")
    parser.add_argument("--project", required=True, help="Unity project path or workspace child folder name")
    parser.add_argument("--timeout", type=float, default=30.0, help="Response timeout in seconds")

    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    subparsers.add_parser("heartbeat", help="Print the current bridge heartbeat")
    subparsers.add_parser("status", help="Request a status snapshot")
    subparsers.add_parser("gameplay", help="Request gameplay, room, and DataRepo snapshot")
    subparsers.add_parser("overview", help="Request a token-compact gameplay overview")
    subparsers.add_parser("definition", help="Describe the active game's engine, flows, blocks, PACs, and actions")

    timeline_parser = subparsers.add_parser("timeline", help="Read structured gameplay events")
    timeline_parser.add_argument("--since", type=int, default=0, help="Only events after this sequence")
    timeline_parser.add_argument("--limit", type=int, default=100)
    timeline_parser.add_argument("--categories", default=None, help="Comma-separated categories: thread,rpc,data")
    timeline_parser.add_argument("--match", default=None, help="Only events containing this text/field/action/node")
    subparsers.add_parser("clear-timeline", help="Clear the structured gameplay journal")
    trace_parser = subparsers.add_parser("trace", help="Enable/disable deep DebugEngine logs for selected blocks")
    trace_parser.add_argument("selectors", help="Comma-separated block/type/title matches; use * explicitly for all")
    trace_parser.add_argument("--phases", default="Execute,GetNextStep")
    trace_parser.add_argument("--disable", action="store_true")

    exceptions_parser = subparsers.add_parser("exceptions", help="Request recent exceptions")
    exceptions_parser.add_argument("--limit", type=int, default=20)
    exceptions_parser.add_argument("--exceptions-only", action="store_true")

    logs_parser = subparsers.add_parser("logs", help="Read recent Unity logs with token-saving filters")
    logs_parser.add_argument("--since", type=int, default=0)
    logs_parser.add_argument("--limit", type=int, default=50)
    logs_parser.add_argument("--types", default=None, help="Comma-separated Log,Warning,Error,Exception,Assert")
    logs_parser.add_argument("--contains", default=None)
    logs_parser.add_argument("--stack", action="store_true", help="Include stack traces")

    open_parser = subparsers.add_parser("open-game", help="Open a game in builder or in the lobby")
    open_parser.add_argument("game_id")
    open_parser.add_argument("--target", default=None, choices=["builder", "lobby"])

    play_parser = subparsers.add_parser("start-local", help="Start a local match")
    play_parser.add_argument("game_id")
    play_parser.add_argument("--player-count", type=int, default=None)
    play_parser.add_argument("--teams", default=None, help="Comma-separated team sizes")
    play_parser.add_argument("--open-builder", action="store_true")

    menu_parser = subparsers.add_parser("menu", help="Execute a Unity menu item")
    menu_parser.add_argument("menu_path")

    shot_parser = subparsers.add_parser("screenshot", help="Capture a screenshot")
    shot_parser.add_argument("--file-name", default=None)

    debug_parser = subparsers.add_parser("debug", help="Invoke a [DebugMethod]")
    debug_parser.add_argument("method_name")
    debug_parser.add_argument("--type", default=None, dest="type_name")
    debug_parser.add_argument("--arguments", default=None, help="JSON array with method arguments")

    subparsers.add_parser("ui-runtime", help="Fetch UI runtime diagnostics snapshot")

    perf_parser = subparsers.add_parser("performance", help="Sample runtime memory and frame metrics")
    perf_parser.add_argument("--duration", type=float, default=10.0, help="Sampling duration in seconds")
    perf_parser.add_argument("--interval-ms", type=int, default=500, help="Sampling interval in milliseconds")
    perf_parser.add_argument("--hitch-ms", type=float, default=50.0, help="Frame time threshold to classify a hitch")
    perf_parser.add_argument("--severe-hitch-ms", type=float, default=100.0, help="Frame time threshold to classify a severe hitch")

    rpc_parser = subparsers.add_parser("rpc", help="Send a gameplay RPC")
    rpc_parser.add_argument("action_id")
    rpc_parser.add_argument("rpc_data_type")
    rpc_parser.add_argument("rpc_data_json", help="JSON object for the rpcData payload")

    raw_parser = subparsers.add_parser("raw", help="Send a raw bridge command")
    raw_parser.add_argument("command")
    raw_parser.add_argument("--args", default="{}", help="JSON object with command args")

    subparsers.add_parser("enter-play", help="Enter Play Mode")
    subparsers.add_parser("exit-play", help="Exit Play Mode")

    return parser


def main() -> int:
    parser = build_parser()
    parsed = parser.parse_args()

    workspace_root = find_workspace_root(Path(__file__))
    project_root = resolve_project_path(parsed.project, workspace_root)
    paths = bridge_paths(project_root)

    if parsed.subcommand == "heartbeat":
        if not paths["heartbeat"].exists():
            raise SystemExit(f"Heartbeat not found at {paths['heartbeat']}")
        print(json.dumps(read_json(paths["heartbeat"]), indent=2))
        return 0

    if parsed.subcommand == "status":
        response = send_request(project_root, "get_status", {}, parsed.timeout)
    elif parsed.subcommand == "gameplay":
        response = send_request(project_root, "get_gameplay_snapshot", {}, parsed.timeout)
    elif parsed.subcommand == "overview":
        response = send_request(project_root, "get_gameplay_overview", {}, parsed.timeout)
    elif parsed.subcommand == "definition":
        response = send_request(project_root, "get_game_definition", {}, parsed.timeout)
    elif parsed.subcommand == "timeline":
        args = {"since": parsed.since, "limit": parsed.limit}
        if parsed.categories:
            args["categories"] = parsed.categories
        if parsed.match:
            args["match"] = parsed.match
        response = send_request(project_root, "get_gameplay_timeline", args, parsed.timeout)
    elif parsed.subcommand == "clear-timeline":
        response = send_request(project_root, "clear_gameplay_timeline", {}, parsed.timeout)
    elif parsed.subcommand == "trace":
        response = send_request(project_root, "configure_gameplay_trace", {
            "selectors": parsed.selectors,
            "phases": parsed.phases,
            "enabled": not parsed.disable,
        }, parsed.timeout)
    elif parsed.subcommand == "exceptions":
        response = send_request(
            project_root,
            "get_recent_exceptions",
            {
                "limit": parsed.limit,
                "includeErrors": not parsed.exceptions_only,
            },
            parsed.timeout,
        )
    elif parsed.subcommand == "logs":
        args = {"since": parsed.since, "limit": parsed.limit, "includeStackTrace": parsed.stack}
        if parsed.types:
            args["types"] = parsed.types
        if parsed.contains:
            args["contains"] = parsed.contains
        response = send_request(project_root, "get_recent_logs", args, parsed.timeout)
    elif parsed.subcommand == "open-game":
        args = {"gameId": parsed.game_id}
        if parsed.target is not None:
            args["target"] = parsed.target
        response = send_request(project_root, "open_game", args, parsed.timeout)
    elif parsed.subcommand == "start-local":
        args = {"gameId": parsed.game_id, "openBuilder": parsed.open_builder}
        if parsed.player_count is not None:
            args["playerCount"] = parsed.player_count
        if parsed.teams:
            args["teamsCount"] = [int(part.strip()) for part in parsed.teams.split(",") if part.strip()]
        response = send_request(project_root, "start_local_match", args, parsed.timeout)
    elif parsed.subcommand == "menu":
        response = send_request(project_root, "execute_menu_item", {"menuPath": parsed.menu_path}, parsed.timeout)
    elif parsed.subcommand == "screenshot":
        args = {}
        if parsed.file_name is not None:
            args["fileName"] = parsed.file_name
        response = send_request(project_root, "capture_screenshot", args, parsed.timeout)
    elif parsed.subcommand == "debug":
        args = {"methodName": parsed.method_name}
        if parsed.type_name:
            args["typeName"] = parsed.type_name
        if parsed.arguments:
            args["arguments"] = json.loads(parsed.arguments)
        response = send_request(project_root, "invoke_debug_method", args, parsed.timeout)
    elif parsed.subcommand == "ui-runtime":
        response = send_request(project_root, "get_ui_runtime_snapshot", {}, parsed.timeout)
    elif parsed.subcommand == "performance":
        response = send_request(
            project_root,
            "sample_performance",
            {
                "durationSeconds": parsed.duration,
                "sampleIntervalMs": parsed.interval_ms,
                "hitchThresholdMs": parsed.hitch_ms,
                "severeHitchThresholdMs": parsed.severe_hitch_ms,
            },
            max(parsed.timeout, parsed.duration + 10.0),
        )
    elif parsed.subcommand == "rpc":
        response = send_request(
            project_root,
            "send_gameplay_rpc",
            {
                "actionId": parsed.action_id,
                "rpcDataType": parsed.rpc_data_type,
                "rpcData": json.loads(parsed.rpc_data_json),
            },
            parsed.timeout,
        )
    elif parsed.subcommand == "enter-play":
        response = send_request(project_root, "enter_play_mode", {}, parsed.timeout)
    elif parsed.subcommand == "exit-play":
        response = send_request(project_root, "exit_play_mode", {}, parsed.timeout)
    elif parsed.subcommand == "raw":
        response = send_request(project_root, parsed.command, json.loads(parsed.args), parsed.timeout)
    else:
        raise SystemExit(f"Unsupported subcommand: {parsed.subcommand}")

    print(json.dumps(response, indent=2))
    return 0 if response.get("success", False) else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except TimeoutError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(2)
