#!/usr/bin/env python3
"""Client for the Unity CLI Pipeline package (`unity command ...`).

This sits alongside `unity_control_bridge.py`, it does not replace it. The two cover
different halves of the job:

  * `unity_control_bridge.py` owns the *domain* vocabulary — open_game, start_local_match,
    send_gameplay_rpc, get_gameplay_snapshot. Nothing here reproduces that.
  * this client owns *inspection* primitives the bridge has no equivalent for — reading a
    live component's serialized fields, and returning a frame the caller can actually look
    at instead of a path to a PNG a human has to open later.

Two hazards in `com.unity.pipeline` 0.4.0-exp.1 that every call here defends against,
because both were hit while wiring this up:

1. Only `--key value` arguments are honoured. Both `key=value` and a JSON payload are
   accepted, answered with `success: true`, and then *silently discarded* — the command
   runs with its defaults. A probe can therefore look like it captured what you asked for
   while capturing something else. `call()` compares the parameters the Editor echoes back
   against what was sent and raises on a mismatch, so a dropped argument is a hard error
   rather than a misleading pass.

2. Anything that triggers a domain reload — recompile, entering Play Mode, run_tests —
   takes the Pipeline HTTP server down with it for as long as the reload lasts. Calls
   retry across that window instead of reporting a connection failure.

`run_tests` is refused outright — see REFUSED_TOOLS. It is not merely unreliable here, it
took the Editor down: async runs do not survive the domain reload they cause (the promised
status file is never written and `test_status` reports `running` forever), synchronous runs
are capped at 30s server-side which this project's EditMode suite blows through, and
cancelling a wedged run leaves the framework throwing `Test tree is not available for
PostbuildCleanupWithTestDataTask` on every subsequent attempt until the Editor exits. Run
EditMode tests the existing way: `./Scripts/dev-check.sh tests`, with the Editor closed.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

# The Editor answers a reload-free command in well under a second; the ceiling is only here
# so a wedged server surfaces as an error instead of hanging a scripted run.
DEFAULT_TIMEOUT = 30

# A domain reload on this project routinely outlasts a minute, and the server is simply absent
# for the whole window rather than answering with an error.
DEFAULT_RELOAD_GRACE = 240.0

UNREACHABLE_MARKERS = (
    "No Unity Editor instances found",
    "ECONNREFUSED",
    "connect ECONNREFUSED",
    "socket hang up",
)

# Driving the test framework from the pipeline left it unable to start another run on
# 2026-08-04: every subsequent attempt threw `Test tree is not available for
# PostbuildCleanupWithTestDataTask`, and the Editor exited shortly after. (The exit itself is
# not firmly attributed — an Editor launched from a tool shell was separately observed exiting
# on process-group cleanup — but the framework damage is reproducible from the logs.) There is
# no configuration that makes these safe here, so the client refuses rather than leaving it to
# each caller to remember why not.
REFUSED_TOOLS = {
    "run_tests": (
        "`run_tests` via com.unity.pipeline is not usable on this project. Async runs lose their "
        "results to the domain reload they trigger (the promised status file is never written and "
        "test_status reports 'running' forever), sync runs hit a 30s server-side cap that the "
        "EditMode suite blows through, and a cancelled run poisons the framework "
        "('Test tree is not available'). Use `./Scripts/dev-check.sh tests` with the Editor closed."
    ),
    "cancel_tests": (
        "`cancel_tests` is what poisons the test framework after a stuck run. "
        "Use `./Scripts/dev-check.sh tests` with the Editor closed."
    ),
}


class PipelineError(RuntimeError):
    """A pipeline call failed in a way the caller cannot paper over."""


class PipelineUnreachable(PipelineError):
    """No Editor is serving the Pipeline HTTP API (often a domain reload in flight)."""


def own_project_root() -> Path:
    """The Unity project this script lives in (`Scripts/..`).

    Deliberately not the CLAUDE.md walk that `unity_control_bridge.py` uses. Every project
    here carries its own one-line `CLAUDE.md`, so that walk stops at the *project* rather than
    the monorepo root, and `--project boardgames` then resolves to `boardgames/boardgames`.
    There is a stray tracked file at exactly that path, so the bad directory even passes an
    exists() check and the mistake surfaces as a confusing "No Pipeline instance found".
    """
    return Path(__file__).resolve().parents[1]


def resolve_project_path(project_arg: str | None) -> Path:
    """Resolve a project path, a bare project name, or nothing at all.

    A bare name is resolved against the monorepo root — the parent of this project — so
    `--project ineuj` works from inside `boardgames/` without pointing at a nested lookalike.
    """
    project_root = own_project_root()
    if not project_arg:
        return project_root

    candidate = Path(project_arg)
    if candidate.is_dir():
        return candidate.resolve()

    sibling = project_root.parent / project_arg
    if sibling.is_dir() and (sibling / "Packages" / "manifest.json").exists():
        return sibling.resolve()

    raise SystemExit(
        f"Project not found: {project_arg}. Pass a path, or a project name that is a sibling "
        f"of {project_root.name} with a Packages/manifest.json."
    )


def _format_value(value) -> str:
    # Unity's arg parser wants the lowercase JSON spelling; Python's str() on a bool gives
    # "True", which the Editor reads as a string and quietly treats as unset.
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


class Pipeline:
    def __init__(
        self,
        project: Path,
        timeout: int = DEFAULT_TIMEOUT,
        reload_grace: float = DEFAULT_RELOAD_GRACE,
        poll_interval: float = 3.0,
        runtime: str | None = None,
        runtime_path: str | None = None,
    ) -> None:
        self.project = project
        self.timeout = timeout
        self.reload_grace = reload_grace
        self.poll_interval = poll_interval
        # Target a running Player instead of the Editor. `runtime` searches by process name,
        # `runtime_path` points at the Player's port descriptor file — the reliable one when
        # several Players of the same project could be up. The Editor remains the default because
        # it is the only side with the control bridge's ~20 domain commands.
        self.runtime = runtime
        self.runtime_path = runtime_path
        self._schemas: dict[str, set[str]] | None = None
        if shutil.which("unity") is None:
            raise PipelineError(
                "The `unity` CLI is not on PATH. Install it with `brew install --cask unity-cli` "
                "(run `brew update` first — a stale cask index hides it)."
            )

    # ---- transport ----------------------------------------------------------------

    def tool_schemas(self) -> dict[str, set[str]]:
        """Parameter names per tool, fetched once from `unity list`.

        This exists because the echo check alone is not enough. The Editor echoes back whatever
        it was sent, including parameters the tool does not define — so passing `--query foo` to
        a tool whose parameter is actually `--name` comes back `success: true` with the argument
        faithfully echoed and completely ignored. Validating names against the real schema is the
        only way to catch that locally.
        """
        if self._schemas is not None:
            return self._schemas
        try:
            completed = subprocess.run(
                ["unity", "list", *self._target_args(), "--format", "json"],
                capture_output=True,
                text=True,
                timeout=60,
            )
            payload = json.loads(completed.stdout)
            # `data` is null when no Editor is serving, which happens routinely mid domain
            # reload — hence `or {}` rather than a default that only covers a missing key.
            tools = (payload.get("data") or {}).get("tools") or []
            self._schemas = {
                tool["name"]: {param["name"] for param in tool.get("parameters", [])}
                for tool in tools
            }
            # Do not cache an empty map: the next call may well reach a live Editor, and caching
            # nothing here would disable name validation for the rest of the run.
            if not self._schemas:
                self._schemas = None
                return {}
        except (subprocess.SubprocessError, json.JSONDecodeError, KeyError, AttributeError, TypeError):
            # Schema validation is a safety net, not a hard dependency: a beta that changes the
            # list format should degrade to the echo check rather than block every call.
            self._schemas = {}
        return self._schemas

    def _target_args(self) -> list[str]:
        """Which Unity this talks to: the project's Editor, or a running Player.

        The flags are mutually exclusive on the CLI side, and `--runtime-path` wins when both are
        given because it names one specific Player rather than matching a process name — with two
        Players of the same build up, name matching is a coin flip.
        """
        if self.runtime_path:
            return ["--runtime-path", str(self.runtime_path)]
        if self.runtime:
            return ["--runtime", str(self.runtime)]
        return ["--project-path", str(self.project)]

    def _invoke(self, tool: str, params: dict) -> tuple[int, str, str]:
        command = [
            "unity",
            "command",
            tool,
            *self._target_args(),
            "--timeout",
            str(self.timeout),
        ]
        for key, value in params.items():
            if value is None:
                continue
            command += [f"--{key}", _format_value(value)]
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            # Give the subprocess more room than the server-side budget so a real server-side
            # timeout is reported as such rather than killed here first.
            timeout=self.timeout + 30,
        )
        return completed.returncode, completed.stdout, completed.stderr

    @staticmethod
    def _parse(stdout: str) -> tuple[dict, dict]:
        """Return (result, echoed_parameters) from the TSV response.

        The human/TSV format is deliberate: `--format json` wraps the same payload but the
        Result column is already JSON, and the TSV header is stable across the beta.
        """
        lines = [line for line in stdout.splitlines() if line.strip()]
        if len(lines) < 2:
            raise PipelineError(f"Unparseable pipeline response: {stdout[:400]!r}")
        columns = lines[1].split("\t")
        if len(columns) < 3:
            raise PipelineError(f"Unexpected pipeline response shape: {lines[1][:400]!r}")

        success = columns[1].strip().lower() == "true"
        raw_result = columns[2].strip()
        try:
            result = json.loads(raw_result) if raw_result else {}
        except json.JSONDecodeError:
            result = {"raw": raw_result}
        echoed = {}
        if len(columns) > 3 and columns[3].strip():
            try:
                echoed = json.loads(columns[3])
            except json.JSONDecodeError:
                echoed = {}
        if not success:
            raise PipelineError(f"Pipeline command failed: {raw_result[:400]}")
        return result, echoed

    def call(self, tool: str, _verify_params: bool = True, **params) -> dict:
        """Run one Editor command, retrying across a domain reload.

        Raises on a parameter mismatch: passing an argument the Editor did not echo back
        means it ran with defaults, and every caller here would rather fail than trust a
        result produced from parameters it did not ask for.
        """
        if tool in REFUSED_TOOLS:
            raise PipelineError(REFUSED_TOOLS[tool])

        sent = {key: value for key, value in params.items() if value is not None}

        known = self.tool_schemas().get(tool)
        if known is not None and sent:
            unknown = sorted(key for key in sent if key not in known)
            if unknown:
                raise PipelineError(
                    f"`{tool}` does not define parameter(s) {unknown}; it would accept them, echo "
                    f"them back, and ignore them. Valid parameters: {sorted(known) or '<none>'}."
                )

        deadline = time.monotonic() + self.reload_grace
        last_error: str | None = None

        while True:
            try:
                code, stdout, stderr = self._invoke(tool, sent)
            except subprocess.TimeoutExpired:
                code, stdout, stderr = 1, "", "local subprocess timeout"

            combined = f"{stdout}\n{stderr}"
            unreachable = any(marker in combined for marker in UNREACHABLE_MARKERS)

            if unreachable:
                last_error = "Pipeline server unreachable"
                if time.monotonic() >= deadline:
                    raise PipelineUnreachable(
                        f"No reachable Pipeline server for {self.project.name} after "
                        f"{self.reload_grace:.0f}s. Is the Editor open with the project loaded, "
                        "and did `unity pipeline install` finish resolving? "
                        "Check with `unity pipeline list`."
                    )
                time.sleep(self.poll_interval)
                continue

            if code != 0:
                raise PipelineError(f"`unity command {tool}` exited {code}: {combined.strip()[:500]}")

            result, echoed = self._parse(stdout)

            if _verify_params and sent:
                missing = sorted(key for key in sent if key not in echoed)
                if missing:
                    raise PipelineError(
                        f"`{tool}` silently ignored parameter(s) {missing} — it ran with defaults. "
                        "This is the 0.4.0-exp.1 arg-parsing trap: only `--key value` is honoured. "
                        f"Sent {sent}, Editor echoed {echoed}."
                    )
            return result

        raise PipelineError(last_error or "unreachable")  # pragma: no cover

    # ---- primitives ---------------------------------------------------------------

    def editor_status(self) -> dict:
        return self.call("editor_status")

    def wait_until_ready(self, timeout: float | None = None) -> dict:
        """Block until the Editor is neither compiling nor mid domain reload."""
        limit = time.monotonic() + (timeout if timeout is not None else self.reload_grace)
        while True:
            status = self.editor_status()
            if not status.get("compiling") and not status.get("domainReloadInProgress"):
                return status
            if time.monotonic() >= limit:
                raise PipelineError(f"Editor never went idle: {status}")
            time.sleep(self.poll_interval)

    def screenshot(self, output: str, view: str = "game") -> dict:
        """Capture a view to a PNG path (project-relative or absolute).

        Prefer this over capture_game_view when a file is what you want: capture_game_view
        returns the image inline as base64, which is hundreds of KB per frame.
        """
        return self.call("screenshot", view=view, output=output)

    def capture_inline(self, width: int = 1280, height: int = 720, max_resolution: int | None = 512) -> dict:
        """Capture a frame and return it inline as base64.

        This is the one thing the control bridge cannot do: the caller sees pixels without a
        human opening a contact sheet. Keep max_resolution small — the payload is the image.
        """
        return self.call(
            "capture_game_view",
            width=width,
            height=height,
            max_resolution=max_resolution,
        )

    def serialized_fields(self, target: str, component: str | None = None, field: str | None = None) -> dict:
        """Read a live component's serialized fields.

        This is what catches the failure class behind the 2026-07-27 incident: a presenter
        that was instantiated, joined the hierarchy and answered RPCs, but whose template data
        resolved to null and got swallowed by `?.`, so it was never configured. Nothing throws,
        so no behavioural test sees it — but the field reads back empty here.
        """
        return self.call("get_serialized_fields", target=target, component=component, field=field)

    def find_gameobjects(
        self,
        name: str | None = None,
        type_name: str | None = None,
        tag: str | None = None,
        hierarchy_path: str | None = None,
    ) -> dict:
        """Find GameObjects by name / component type / tag / hierarchy path (filters combine).

        There is no free-text query and no limit: the tool takes exact matches only, and passing
        an invented `query`/`limit` is accepted, echoed and ignored. Returns a `gameObjects` list
        whose `globalId` and `hierarchyPath` are valid targets for serialized_fields().
        """
        return self.call(
            "find_gameobjects",
            name=name,
            type=type_name,
            tag=tag,
            hierarchy_path=hierarchy_path,
        )

    def scene_hierarchy(self, **params) -> dict:
        return self.call("get_scene_hierarchy", **params)

    def console_logs(self, severity: str | None = None, limit: int | None = None) -> dict:
        return self.call("get_console_logs", severity=severity, limit=limit)

    def set_autotick(self, enable: bool = True, interval_ms: int = 16) -> dict:
        """Keep the Editor ticking while unfocused.

        Without this a backgrounded Editor will not even notice a manifest change, let alone
        advance a match between captures.
        """
        return self.call("set_autotick", enable=enable, interval_ms=interval_ms)


# ---- CLI ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Talk to the Unity Pipeline package.")
    parser.add_argument(
        "--project",
        default=None,
        help="Project path or sibling project name. Defaults to the project this script lives in.",
    )
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)
    parser.add_argument(
        "--runtime",
        help="Talk to a running Player instead of the Editor, matched by process name.",
    )
    parser.add_argument(
        "--runtime-path",
        help="Talk to a running Player identified by its port descriptor file. Beats --runtime.",
    )
    parser.add_argument("--reload-grace", type=float, default=DEFAULT_RELOAD_GRACE)
    parser.add_argument("--json", action="store_true", help="Print the raw JSON result.")

    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status", help="Editor status (compiling / domain reload / play mode).")
    sub.add_parser("tools", help="Count and list the tools the Editor exposes.")

    shot = sub.add_parser("screenshot", help="Capture a view to a PNG.")
    shot.add_argument("output")
    shot.add_argument("--view", default="game", choices=["game", "scene"])

    fields = sub.add_parser("fields", help="Read a component's serialized fields.")
    fields.add_argument("target", help="globalId / path / guid / instanceId / hierarchyPath")
    fields.add_argument("--component")
    fields.add_argument("--field")

    find = sub.add_parser("find", help="Find GameObjects by exact name / type / tag / path.")
    find.add_argument("--name")
    find.add_argument("--type", dest="type_name", help="Component type, e.g. UnityEngine.Camera")
    find.add_argument("--tag")
    find.add_argument("--hierarchy-path")

    logs = sub.add_parser("logs", help="Read recent Editor console logs.")
    logs.add_argument("--severity")
    logs.add_argument("--limit", type=int, default=50)

    tick = sub.add_parser("autotick", help="Keep the Editor ticking while unfocused.")
    tick.add_argument("--disable", action="store_true")
    tick.add_argument("--interval-ms", type=int, default=16)

    raw = sub.add_parser("call", help="Call any tool: call <tool> [--key value ...]")
    raw.add_argument("tool")
    raw.add_argument("args", nargs=argparse.REMAINDER)

    return parser


def parse_raw_args(tokens: list[str]) -> dict:
    params: dict[str, str] = {}
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if not token.startswith("--"):
            raise SystemExit(
                f"Expected --key value, got {token!r}. Only `--key value` is honoured by the "
                "Pipeline package; key=value is silently ignored."
            )
        key = token[2:]
        if index + 1 >= len(tokens) or tokens[index + 1].startswith("--"):
            params[key] = "true"
            index += 1
        else:
            params[key] = tokens[index + 1]
            index += 2
    return params


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    project = resolve_project_path(args.project)
    pipeline = Pipeline(
        project,
        timeout=args.timeout,
        reload_grace=args.reload_grace,
        runtime=args.runtime,
        runtime_path=args.runtime_path,
    )

    try:
        if args.command == "status":
            result = pipeline.editor_status()
        elif args.command == "tools":
            result = _list_tools(pipeline)
        elif args.command == "screenshot":
            result = pipeline.screenshot(args.output, view=args.view)
        elif args.command == "fields":
            result = pipeline.serialized_fields(args.target, component=args.component, field=args.field)
        elif args.command == "find":
            result = pipeline.find_gameobjects(
                name=args.name,
                type_name=args.type_name,
                tag=args.tag,
                hierarchy_path=args.hierarchy_path,
            )
        elif args.command == "logs":
            result = pipeline.console_logs(severity=args.severity, limit=args.limit)
        elif args.command == "autotick":
            result = pipeline.set_autotick(enable=not args.disable, interval_ms=args.interval_ms)
        elif args.command == "call":
            result = pipeline.call(args.tool, **parse_raw_args(args.args))
        else:  # pragma: no cover
            parser.error(f"Unhandled command {args.command}")
            return 2
    except PipelineError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(json.dumps(result, indent=2))
    return 0


def _list_tools(pipeline: "Pipeline") -> dict:
    completed = subprocess.run(
        ["unity", "list", *pipeline._target_args(), "--format", "json"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if completed.returncode != 0:
        raise PipelineError(completed.stderr.strip()[:400])
    payload = json.loads(completed.stdout)
    tools = payload.get("data", {}).get("tools", [])
    return {"count": len(tools), "names": sorted(tool["name"] for tool in tools)}


if __name__ == "__main__":
    raise SystemExit(main())
