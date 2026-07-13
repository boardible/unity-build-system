#!/usr/bin/env python3

import argparse
import json
import shutil
import sys
import time
from pathlib import Path
from typing import Callable

from unity_control_bridge import read_json
from unity_control_bridge import resolve_project_path
from unity_control_bridge import find_workspace_root
from unity_control_bridge import bridge_paths
from unity_control_bridge import send_request


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run automated Unity bridge scenarios")
    parser.add_argument("--project", default="boardgames", help="Unity project path or workspace child folder name")
    parser.add_argument("--timeout", type=float, default=30.0, help="Per-request timeout in seconds")
    parser.add_argument("--screenshot-timeout", type=float, default=45.0, help="Screenshot request timeout in seconds")
    parser.add_argument("--wait-timeout", type=float, default=60.0, help="Polling timeout in seconds")
    parser.add_argument("--poll-interval", type=float, default=1.0, help="Polling interval in seconds")
    parser.add_argument("--output", default=None, help="Optional path to write the JSON result")
    parser.add_argument("--artifact-prefix", default="", help="Prefix screenshot artifacts, typically a run id")
    parser.add_argument("--allow-exceptions", action="store_true", help="Do not fail the scenario when bridge exceptions are found")
    parser.add_argument("--skip-screenshot", action="store_true", help="Skip screenshot capture when only status/evidence JSON is needed")
    parser.add_argument("--quiet", action="store_true", help="Write --output without printing the full JSON payload")

    subparsers = parser.add_subparsers(dest="scenario", required=True)

    subparsers.add_parser("baseline", help="Capture baseline status, exceptions, and a screenshot")
    subparsers.add_parser("onboarding-reset", help="Reset player data and prove onboarding is reachable again")
    subparsers.add_parser("cold-boot-basic", help="Exit Play Mode, enter again, and prove cold boot reaches runtime without recent exceptions")

    cold_boot_parser = subparsers.add_parser("measure-cold-boot", help="Sample performance from Play Mode entry through cold boot")
    cold_boot_parser.add_argument("--duration", type=float, default=20.0)
    cold_boot_parser.add_argument("--interval-ms", type=int, default=500)

    menu_idle_parser = subparsers.add_parser("measure-menu-idle", help="Sample performance while the main menu stays idle")
    menu_idle_parser.add_argument("--duration", type=float, default=20.0)
    menu_idle_parser.add_argument("--interval-ms", type=int, default=500)

    onboarding_nav_parser = subparsers.add_parser("measure-onboarding-nav", help="Sample onboarding startup after a reset and first navigation actions")
    onboarding_nav_parser.add_argument("--touch-duration", type=float, default=5.0)
    onboarding_nav_parser.add_argument("--profile-duration", type=float, default=10.0)
    onboarding_nav_parser.add_argument("--interval-ms", type=int, default=250)
    onboarding_nav_parser.add_argument("--profile", default="new", choices=["new", "casual", "hardcore"])

    corrupt_upgrade_parser = subparsers.add_parser(
        "upgrade-corrupt-cache",
        help="Seed legacy and malformed local cache data, then prove boot recovers into a valid route",
    )
    corrupt_upgrade_parser.add_argument(
        "--completed-onboarding",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Expect the recovered route to land on the main menu instead of onboarding",
    )

    open_game_parser = subparsers.add_parser("open-game", help="Open a game through the bridge")
    open_game_parser.add_argument("game_id")
    open_game_parser.add_argument("--target", default="lobby", choices=["builder", "lobby"])

    start_local_parser = subparsers.add_parser("start-local", help="Start a local match through the bridge")
    start_local_parser.add_argument("game_id")
    start_local_parser.add_argument("--player-count", type=int, default=None)
    start_local_parser.add_argument("--teams", default=None, help="Comma-separated team sizes")
    start_local_parser.add_argument("--open-builder", action="store_true")

    return parser


class ScenarioFailure(RuntimeError):
    pass


class BridgeScenarioRunner:
    def __init__(self, parsed: argparse.Namespace):
        workspace_root = find_workspace_root(Path(__file__))
        self.project_root = resolve_project_path(parsed.project, workspace_root)
        self.paths = bridge_paths(self.project_root)
        self.timeout = parsed.timeout
        self.screenshot_timeout = parsed.screenshot_timeout
        self.wait_timeout = parsed.wait_timeout
        self.poll_interval = parsed.poll_interval
        self.allow_exceptions = parsed.allow_exceptions
        self.skip_screenshot = parsed.skip_screenshot
        self.artifact_prefix = parsed.artifact_prefix
        self.output_path = Path(parsed.output).resolve() if parsed.output else None

    def heartbeat(self, required_capabilities: set[str] | None = None) -> dict:
        heartbeat_path = self.paths["heartbeat"]
        if not heartbeat_path.exists():
            raise ScenarioFailure(f"Bridge heartbeat not found at {heartbeat_path}")

        heartbeat = read_json(heartbeat_path)
        required_capabilities = required_capabilities or set()
        capabilities = set(heartbeat.get("capabilities", []))
        missing = sorted(required_capabilities - capabilities)
        if missing:
            raise ScenarioFailure(f"Bridge heartbeat is missing capabilities: {', '.join(missing)}")

        return heartbeat

    @staticmethod
    def capabilities_for(*names: str) -> set[str]:
        return set(names)

    def request(self, command: str, args: dict | None = None, timeout: float | None = None) -> dict:
        response = send_request(self.project_root, command, args or {}, timeout or self.timeout)
        if not response.get("success", False):
            raise ScenarioFailure(f"Bridge command '{command}' failed: {json.dumps(response, indent=2)}")
        return response

    def status(self) -> dict:
        return self.request("get_status")["result"]

    def gameplay_snapshot(self) -> dict:
        return self.request("get_gameplay_snapshot")["result"]

    def gameplay_overview(self) -> dict:
        return self.request("get_gameplay_overview")["result"]

    def gameplay_timeline(self, since: int = 0, limit: int = 200, categories: str | None = None) -> dict:
        args = {"since": since, "limit": limit}
        if categories:
            args["categories"] = categories
        return self.request("get_gameplay_timeline", args)["result"]

    def recent_exceptions(self, limit: int = 20) -> dict:
        return self.request(
            "get_recent_exceptions",
            {
                "limit": limit,
                "includeErrors": True,
            },
        )["result"]

    def exception_markers(self, limit: int = 20) -> set[tuple[str | None, str | None]]:
        exceptions = self.recent_exceptions(limit=limit)
        return {
            (entry.get("timestampUtc"), entry.get("condition"))
            for entry in exceptions.get("entries", [])
        }

    def safe_exception_markers(self, limit: int = 20) -> set[tuple[str | None, str | None]] | None:
        try:
            return self.exception_markers(limit=limit)
        except TimeoutError:
            return None

    def safe_collect_exception_evidence(self, known_markers: set[tuple[str | None, str | None]] | None = None) -> dict:
        try:
            return self.collect_exception_evidence(known_markers=known_markers)
        except TimeoutError:
            return {
                "count": None,
                "entries": [],
                "timedOut": True,
            }

    def enter_play_mode(self) -> dict:
        return self.request("enter_play_mode")["result"]

    def exit_play_mode(self) -> dict:
        return self.request("exit_play_mode")["result"]

    def focus_game_view(self) -> dict:
        return self.request("execute_menu_item", {"menuPath": "Window/General/Game"})["result"]

    def screenshot(self, file_name: str) -> dict:
        if self.skip_screenshot:
            return {
                "skipped": True,
                "reason": "skip-screenshot flag enabled",
            }

        file_name = f"{self.artifact_prefix}{file_name}"
        self.focus_game_view()
        self.status()
        result = self.request("capture_screenshot", {"fileName": file_name}, timeout=self.screenshot_timeout)["result"]
        source_path = Path(result.get("path", ""))
        if self.output_path and source_path.is_file():
            self.output_path.parent.mkdir(parents=True, exist_ok=True)
            destination = self.output_path.parent / source_path.name
            shutil.copy2(source_path, destination)
            result["bridgePath"] = str(source_path)
            result["path"] = str(destination)
        return result

    def invoke_debug_method(self, method_name: str, type_name: str | None = None, arguments: list | None = None) -> dict:
        args = {"methodName": method_name}
        if type_name is not None:
            args["typeName"] = type_name
        if arguments is not None:
            args["arguments"] = arguments
        return self.request("invoke_debug_method", args)["result"]

    def sample_performance(self, duration_seconds: float, sample_interval_ms: int) -> dict:
        timeout_seconds = max(self.timeout, duration_seconds + 10.0)
        return self.request(
            "sample_performance",
            {
                "durationSeconds": duration_seconds,
                "sampleIntervalMs": sample_interval_ms,
            },
            timeout=timeout_seconds,
        )["result"]

    def wait_for_status(self, predicate: Callable[[dict], bool], description: str) -> dict:
        deadline = time.time() + self.wait_timeout
        last_status = None
        last_error = None

        while time.time() < deadline:
            try:
                last_status = self.status()
                if predicate(last_status):
                    return last_status
            except TimeoutError as error:
                last_error = str(error)
            time.sleep(self.poll_interval)

        if last_error and last_status is None:
            raise ScenarioFailure(f"Timed out waiting for {description}. Last bridge error: {last_error}")

        raise ScenarioFailure(
            f"Timed out waiting for {description}. Last status: {json.dumps(last_status, indent=2)}"
        )

    def wait_for_status_with_timeout(self, predicate: Callable[[dict], bool], description: str, timeout_seconds: float) -> dict | None:
        deadline = time.time() + timeout_seconds

        while time.time() < deadline:
            try:
                snapshot = self.status()
                if predicate(snapshot):
                    return snapshot
            except TimeoutError:
                pass
            time.sleep(self.poll_interval)

        return None

    def wait_for_debug_method(self, method_name: str, type_name: str, description: str, arguments: list | None = None) -> dict:
        deadline = time.time() + self.wait_timeout
        last_error = None

        while time.time() < deadline:
            try:
                return self.invoke_debug_method(method_name, type_name=type_name, arguments=arguments)
            except ScenarioFailure as error:
                last_error = str(error)
                time.sleep(self.poll_interval)

        raise ScenarioFailure(f"Timed out waiting for {description}. Last error: {last_error}")

    def wait_for_debug_predicate(
        self,
        method_name: str,
        type_name: str,
        predicate: Callable[[dict], bool],
        description: str,
        arguments: list | None = None,
    ) -> dict:
        deadline = time.time() + self.wait_timeout
        last_error = None
        last_result = None

        while time.time() < deadline:
            try:
                last_result = self.invoke_debug_method(method_name, type_name=type_name, arguments=arguments)
                if predicate(last_result.get("result")):
                    return last_result
            except ScenarioFailure as error:
                last_error = str(error)

            time.sleep(self.poll_interval)

        raise ScenarioFailure(
            f"Timed out waiting for {description}. Last result: {json.dumps(last_result, indent=2) if last_result is not None else last_error}"
        )

    def ensure_runtime_ready(self) -> dict:
        deadline = time.time() + self.wait_timeout
        last_status = None
        last_enter_attempt_at = 0.0

        while time.time() < deadline:
            last_status = self.status()
            if last_status.get("isPlaying") and last_status.get("objects", {}).get("appRoom"):
                return last_status

            now = time.time()
            if (
                not last_status.get("isPlaying")
                and not last_status.get("isPlayingOrWillChangePlaymode", False)
                and now - last_enter_attempt_at >= max(self.poll_interval, 1.0)
            ):
                self.enter_play_mode()
                last_enter_attempt_at = now

            time.sleep(self.poll_interval)

        raise ScenarioFailure(
            f"Timed out waiting for Play Mode with AppRoom loaded. Last status: {json.dumps(last_status, indent=2)}"
        )

    def collect_exception_evidence(self, known_markers: set[tuple[str | None, str | None]] | None = None) -> dict:
        exceptions = self.recent_exceptions()
        entries = exceptions.get("entries", [])
        if known_markers is not None:
            entries = [
                entry for entry in entries
                if (entry.get("timestampUtc"), entry.get("condition")) not in known_markers
            ]
            exceptions = {
                **exceptions,
                "count": len(entries),
                "entries": entries,
            }
        if entries and not self.allow_exceptions:
            raise ScenarioFailure(f"Bridge reported recent exceptions: {json.dumps(exceptions, indent=2)}")
        return exceptions

    def run_baseline(self) -> dict:
        heartbeat = self.heartbeat(
            self.capabilities_for(
                "get_status",
                "get_recent_exceptions",
                "enter_play_mode",
                "capture_screenshot",
                "execute_menu_item",
            )
        )
        known_markers = self.safe_exception_markers()
        status = self.ensure_runtime_ready()
        exceptions = self.safe_collect_exception_evidence(known_markers=known_markers)
        screenshot = self.screenshot("bridge-baseline.png")

        return {
            "scenario": "baseline",
            "heartbeat": heartbeat,
            "status": status,
            "exceptions": exceptions,
            "screenshot": screenshot,
        }

    def run_onboarding_reset(self) -> dict:
        heartbeat = self.heartbeat(
            self.capabilities_for(
                "get_status",
                "get_recent_exceptions",
                "enter_play_mode",
                "capture_screenshot",
                "execute_menu_item",
                "invoke_debug_method",
            )
        )
        known_markers = self.safe_exception_markers()
        self.ensure_runtime_ready()

        reset_result = self.invoke_debug_method(
            "ResetToFreshOnboarding",
        )
        status = self.wait_for_status(
            lambda snapshot: snapshot.get("isPlaying") and snapshot.get("objects", {}).get("appRoom"),
            "fresh onboarding state after reset",
        )
        onboarding_step = self.wait_for_debug_method(
            "DebugGetStepIndex",
            type_name="Boardible.MainMenu.OnboUIScreen",
            description="Onboarding screen availability",
        )
        exceptions = self.safe_collect_exception_evidence(known_markers=known_markers)
        screenshot = self.screenshot("bridge-onboarding-reset.png")

        return {
            "scenario": "onboarding-reset",
            "heartbeat": heartbeat,
            "reset": reset_result,
            "status": status,
            "onboardingStep": onboarding_step,
            "exceptions": exceptions,
            "screenshot": screenshot,
        }

    def run_cold_boot_basic(self) -> dict:
        heartbeat = self.heartbeat(
            self.capabilities_for(
                "get_status",
                "get_recent_exceptions",
                "enter_play_mode",
                "exit_play_mode",
                "capture_screenshot",
                "execute_menu_item",
            )
        )
        known_markers = self.safe_exception_markers()

        if self.status().get("isPlaying"):
            self.exit_play_mode()
            self.wait_for_status(lambda snapshot: not snapshot.get("isPlaying"), "Edit Mode before cold boot validation")

        self.enter_play_mode()
        status = self.wait_for_status(
            lambda snapshot: snapshot.get("isPlaying") and snapshot.get("objects", {}).get("appRoom"),
            "Play Mode with AppRoom loaded after cold boot",
        )
        exceptions = self.safe_collect_exception_evidence(known_markers=known_markers)
        screenshot = self.screenshot("bridge-cold-boot-basic.png")

        return {
            "scenario": "cold-boot-basic",
            "heartbeat": heartbeat,
            "status": status,
            "exceptions": exceptions,
            "screenshot": screenshot,
        }

    def run_measure_cold_boot(self, duration_seconds: float, sample_interval_ms: int) -> dict:
        heartbeat = self.heartbeat(
            self.capabilities_for(
                "get_status",
                "get_recent_exceptions",
                "enter_play_mode",
                "exit_play_mode",
                "sample_performance",
            )
        )
        known_markers = self.safe_exception_markers()

        if self.status().get("isPlaying"):
            self.exit_play_mode()
            self.wait_for_status(lambda snapshot: not snapshot.get("isPlaying"), "Edit Mode before cold boot sampling")

        self.enter_play_mode()
        self.wait_for_status(lambda snapshot: snapshot.get("isPlaying"), "Play Mode before cold boot sampling")
        performance = self.sample_performance(duration_seconds, sample_interval_ms)
        status = self.wait_for_status(
            lambda snapshot: snapshot.get("isPlaying") and snapshot.get("objects", {}).get("appRoom"),
            "Play Mode with AppRoom loaded after cold boot sampling",
        )
        exceptions = self.safe_collect_exception_evidence(known_markers=known_markers)

        return {
            "scenario": "measure-cold-boot",
            "heartbeat": heartbeat,
            "performance": performance,
            "status": status,
            "exceptions": exceptions,
        }

    def run_measure_menu_idle(self, duration_seconds: float, sample_interval_ms: int) -> dict:
        heartbeat = self.heartbeat(
            self.capabilities_for(
                "get_status",
                "get_recent_exceptions",
                "enter_play_mode",
                "sample_performance",
            )
        )
        known_markers = self.safe_exception_markers()
        status_before = self.ensure_runtime_ready()
        performance = self.sample_performance(duration_seconds, sample_interval_ms)
        status_after = self.status()
        exceptions = self.safe_collect_exception_evidence(known_markers=known_markers)

        return {
            "scenario": "measure-menu-idle",
            "heartbeat": heartbeat,
            "statusBefore": status_before,
            "performance": performance,
            "statusAfter": status_after,
            "exceptions": exceptions,
        }

    def run_measure_onboarding_nav(
        self,
        touch_duration_seconds: float,
        profile_duration_seconds: float,
        sample_interval_ms: int,
        profile: str,
    ) -> dict:
        heartbeat = self.heartbeat(
            self.capabilities_for(
                "get_status",
                "get_recent_exceptions",
                "enter_play_mode",
                "invoke_debug_method",
                "sample_performance",
            )
        )
        known_markers = self.safe_exception_markers()
        self.ensure_runtime_ready()

        reset_result = self.invoke_debug_method("ResetToFreshOnboarding")
        initial_step = self.wait_for_debug_predicate(
            "DebugGetStepIndex",
            type_name="Boardible.MainMenu.OnboUIScreen",
            predicate=lambda value: isinstance(value, int) and value == 0,
            description="onboarding step 0 after reset",
        )

        self.invoke_debug_method("DebugTouchToStart", type_name="Boardible.MainMenu.OnboUIScreen")
        touch_performance = self.sample_performance(touch_duration_seconds, sample_interval_ms)
        step_after_touch = self.wait_for_debug_predicate(
            "DebugGetStepIndex",
            type_name="Boardible.MainMenu.OnboUIScreen",
            predicate=lambda value: isinstance(value, int) and value >= 1,
            description="onboarding step after touch-to-start",
        )

        self.invoke_debug_method("DebugSelectProfile", type_name="Boardible.MainMenu.OnboUIScreen", arguments=[profile])
        profile_performance = self.sample_performance(profile_duration_seconds, sample_interval_ms)
        expected_step = 3 if profile == "new" else 2
        step_after_profile = self.wait_for_debug_predicate(
            "DebugGetStepIndex",
            type_name="Boardible.MainMenu.OnboUIScreen",
            predicate=lambda value: isinstance(value, int) and value >= expected_step,
            description=f"onboarding step {expected_step} after selecting profile '{profile}'",
        )

        status = self.status()
        exceptions = self.safe_collect_exception_evidence(known_markers=known_markers)

        return {
            "scenario": "measure-onboarding-nav",
            "heartbeat": heartbeat,
            "reset": reset_result,
            "initialStep": initial_step,
            "touchPerformance": touch_performance,
            "stepAfterTouch": step_after_touch,
            "profile": profile,
            "profilePerformance": profile_performance,
            "stepAfterProfile": step_after_profile,
            "status": status,
            "exceptions": exceptions,
        }

    def run_upgrade_corrupt_cache(self, completed_onboarding: bool) -> dict:
        heartbeat = self.heartbeat(
            self.capabilities_for(
                "get_status",
                "get_recent_exceptions",
                "enter_play_mode",
                "invoke_debug_method",
                "capture_screenshot",
                "execute_menu_item",
            )
        )
        known_markers = self.safe_exception_markers()
        self.ensure_runtime_ready()

        expected_route = "main" if completed_onboarding else "onboarding"
        recovery = self.invoke_debug_method(
            "RecoverFromCorruptedUpgradeCache",
            arguments=[completed_onboarding],
        )
        if recovery.get("result") != expected_route:
            raise ScenarioFailure(
                f"Corrupted upgrade recovery landed on '{recovery.get('result')}', expected '{expected_route}'."
            )

        status = self.status()
        onboarding_step = None
        if not completed_onboarding:
            onboarding_step = self.wait_for_debug_method(
                "DebugGetStepIndex",
                type_name="Boardible.MainMenu.OnboUIScreen",
                description="Onboarding screen availability after corrupted upgrade recovery",
            )

        exceptions = self.safe_collect_exception_evidence(known_markers=known_markers)
        screenshot = self.screenshot("bridge-upgrade-corrupt-cache.png")

        return {
            "scenario": "upgrade-corrupt-cache",
            "heartbeat": heartbeat,
            "expectedRoute": expected_route,
            "recovery": recovery,
            "status": status,
            "onboardingStep": onboarding_step,
            "exceptions": exceptions,
            "screenshot": screenshot,
        }

    def run_open_game(self, game_id: str, target: str) -> dict:
        heartbeat = self.heartbeat(
            self.capabilities_for(
                "get_status",
                "get_recent_exceptions",
                "enter_play_mode",
                "open_game",
                "capture_screenshot",
                "execute_menu_item",
            )
        )
        known_markers = self.safe_exception_markers()
        self.ensure_runtime_ready()

        open_result = self.request("open_game", {"gameId": game_id, "target": target})["result"]
        status = self.wait_for_status(
            lambda snapshot: target == "builder" or snapshot.get("room", {}).get("gameId") == game_id,
            f"game '{game_id}' to open on target '{target}'",
        )
        exceptions = self.safe_collect_exception_evidence(known_markers=known_markers)
        screenshot = self.screenshot(f"bridge-open-{game_id}.png")

        return {
            "scenario": "open-game",
            "heartbeat": heartbeat,
            "result": open_result,
            "status": status,
            "exceptions": exceptions,
            "screenshot": screenshot,
        }

    def run_start_local(self, game_id: str, player_count: int | None, teams: str | None, open_builder: bool) -> dict:
        heartbeat = self.heartbeat(
            self.capabilities_for(
                "get_status",
                "get_gameplay_snapshot",
                "get_gameplay_overview",
                "get_gameplay_timeline",
                "get_recent_exceptions",
                "enter_play_mode",
                "start_local_match",
                "capture_screenshot",
                "execute_menu_item",
            )
        )
        known_markers = self.safe_exception_markers()
        self.ensure_runtime_ready()
        timeline_before = self.gameplay_timeline(limit=1)
        timeline_cursor = int(timeline_before.get("cursor", 0))

        args = {"gameId": game_id, "openBuilder": open_builder}
        if player_count is not None:
            args["playerCount"] = player_count
        if teams:
            args["teamsCount"] = [int(part.strip()) for part in teams.split(",") if part.strip()]

        start_result = self.request("start_local_match", args, timeout=max(self.timeout, 60.0))["result"]
        status = self.wait_for_status(
            lambda snapshot: snapshot.get("gameController", {}).get("gameId") == game_id,
            f"local match '{game_id}' to start",
        )
        gameplay = self.gameplay_snapshot()
        overview = self.gameplay_overview()
        timeline = self.gameplay_timeline(since=timeline_cursor, limit=300, categories="thread,rpc,data")
        exceptions = self.safe_collect_exception_evidence(known_markers=known_markers)
        screenshot = self.screenshot(f"bridge-local-{game_id}.png")

        return {
            "scenario": "start-local",
            "heartbeat": heartbeat,
            "result": start_result,
            "status": status,
            "gameplay": gameplay,
            "overview": overview,
            "timeline": timeline,
            "exceptions": exceptions,
            "screenshot": screenshot,
        }


def main() -> int:
    parser = build_parser()
    parsed = parser.parse_args()

    runner = BridgeScenarioRunner(parsed)

    try:
        if parsed.scenario == "baseline":
            result = runner.run_baseline()
        elif parsed.scenario == "onboarding-reset":
            result = runner.run_onboarding_reset()
        elif parsed.scenario == "cold-boot-basic":
            result = runner.run_cold_boot_basic()
        elif parsed.scenario == "measure-cold-boot":
            result = runner.run_measure_cold_boot(parsed.duration, parsed.interval_ms)
        elif parsed.scenario == "measure-menu-idle":
            result = runner.run_measure_menu_idle(parsed.duration, parsed.interval_ms)
        elif parsed.scenario == "measure-onboarding-nav":
            result = runner.run_measure_onboarding_nav(
                parsed.touch_duration,
                parsed.profile_duration,
                parsed.interval_ms,
                parsed.profile,
            )
        elif parsed.scenario == "upgrade-corrupt-cache":
            result = runner.run_upgrade_corrupt_cache(parsed.completed_onboarding)
        elif parsed.scenario == "open-game":
            result = runner.run_open_game(parsed.game_id, parsed.target)
        elif parsed.scenario == "start-local":
            result = runner.run_start_local(parsed.game_id, parsed.player_count, parsed.teams, parsed.open_builder)
        else:
            raise ScenarioFailure(f"Unsupported scenario: {parsed.scenario}")
    except ScenarioFailure as error:
        if parsed.output:
            output_path = Path(parsed.output)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(json.dumps({
                "scenario": parsed.scenario,
                "status": "failed",
                "error": str(error),
            }, indent=2) + "\n", encoding="utf-8")
        print(str(error), file=sys.stderr)
        return 1

    payload = json.dumps(result, indent=2)
    if not parsed.quiet:
        print(payload)

    if parsed.output:
        output_path = Path(parsed.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(payload + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
