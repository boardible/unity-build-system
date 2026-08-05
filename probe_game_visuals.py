#!/usr/bin/env python3
"""Prove a game actually renders, and report it in a form an agent can read.

Why this exists
---------------
Smoke asserts flow progression, RPCs and a scoring oracle. It asserts nothing about whether
anything reached the screen — that is how BDB_Cards and LeTruc were both reported done on an
8/8 pass while being visually unplayable. `dev-check.sh walkthrough` already screenshots each
checkpoint, but it writes an HTML contact sheet for a *human* to open later, so the verdict
still waits on someone looking at it.

This probe closes that specific gap: it returns each frame inline (base64, downscaled) next to
the error delta and, where available, the serialized state of the objects that were supposed to
be configured. That makes "did this render, and is it wired" answerable in the same breath as
"did the flow advance", without a human in the loop.

Division of labour
------------------
Match setup is delegated to `run_bridge_scenarios.py start-local`, which already owns the
domain vocabulary (open_game / start_local_match) and — importantly — already knows to wait for
`objects.appCoreConnection` before starting, because this app is not offline-first and
`AppRoom.HandleChangeGame` throws on a null gameSetup otherwise. Nothing here reimplements that.

Inspection is done through `unity_pipeline.py` (the Unity CLI Pipeline package), which is the
only side that can hand a frame back inline and read a live component's serialized fields.

What a green result does and does not mean
-----------------------------------------
Green means: the match started, frames rendered with real content, and no new errors appeared.
It does NOT mean the game is playable or the rules are right. Read the frames.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from unity_pipeline import Pipeline, PipelineError, resolve_project_path  # noqa: E402

# A frame that is a flat expanse of one colour is the signature of the documented empty-scene
# trap (Play Mode entered with no scene loaded renders an empty skybox). Distinguishing that
# from a real frame is the whole point, so it is measured rather than eyeballed.
FLAT_FRAME_UNIQUE_COLOUR_CEILING = 24


class ProbeFailure(RuntimeError):
    pass


def resolve_boot_scene(project: Path, explicit: str | None) -> tuple[str, str]:
    """Work out which scene must be loaded for this project, and say where that came from.

    The three Unity projects do not agree on the path — boardgames and ineuj use
    `Assets/App/Scenes/GameBoxScene.unity`, tictac uses `Assets/App/Boot/Scenes/GameBoxScene.unity`
    — so this cannot be hardcoded in shared `Scripts/` code.

    Precedence: explicit flag, then `UNITY_BOOT_SCENE` from the project's `project-config.sh`
    (exported by `load_project_config`, the same pattern the rest of this directory uses), then
    the first scene in the project's own Build Settings. The Build Settings fallback exists so a
    project that has not set the variable yet still gets the right answer instead of a silently
    wrong default.
    """
    if explicit:
        return explicit, "--boot-scene"

    from_env = os.environ.get("UNITY_BOOT_SCENE")
    if from_env:
        return from_env, "UNITY_BOOT_SCENE"

    build_settings = project / "ProjectSettings" / "EditorBuildSettings.asset"
    if build_settings.exists():
        match = re.search(r"(Assets/[\w/\-. ]+\.unity)", build_settings.read_text(encoding="utf-8", errors="replace"))
        if match:
            return match.group(1), "EditorBuildSettings.asset"

    raise ProbeFailure(
        "Could not determine the boot scene. Set UNITY_BOOT_SCENE in the project's "
        "project-config.sh, or pass --boot-scene."
    )


def run_bridge_scenario(project: Path, game_id: str, extra: list[str], timeout: int) -> dict:
    """Start a local match through the existing bridge scenario runner."""
    output = project / "Temp" / f"probe-start-local-{game_id}.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        sys.executable,
        str(SCRIPT_DIR / "run_bridge_scenarios.py"),
        "--project",
        str(project),
        "--timeout",
        "180",
        "--wait-timeout",
        "420",
        "--output",
        str(output),
        "--quiet",
        "start-local",
        game_id,
        *extra,
    ]
    completed = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    payload = {}
    if output.exists():
        try:
            payload = json.loads(output.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            payload = {}
    return {
        "exitCode": completed.returncode,
        "stderrTail": completed.stderr.strip()[-800:],
        "report": payload,
    }


def describe_frame(png_path: Path) -> dict:
    """Summarise a captured PNG without a human opening it.

    Uses PIL when it is available and degrades to a size check when it is not, because this
    project's venv is not guaranteed to carry Pillow and a missing optional dependency should
    not fail a probe whose real payload is the image itself.
    """
    info: dict = {"bytes": png_path.stat().st_size if png_path.exists() else 0}
    if not png_path.exists():
        info["error"] = "capture reported success but no file was written"
        return info
    try:
        from PIL import Image  # type: ignore
    except ImportError:
        info["analysis"] = "unavailable (Pillow not installed)"
        return info

    with Image.open(png_path) as image:
        info["size"] = list(image.size)
        thumbnail = image.convert("RGB").resize((64, 64))
        colours = thumbnail.getcolors(maxcolors=64 * 64) or []
        info["uniqueColours"] = len(colours)
        info["looksFlat"] = len(colours) <= FLAT_FRAME_UNIQUE_COLOUR_CEILING
    return info


class GameProbe:
    def __init__(self, pipeline: Pipeline, project: Path, run_root: Path) -> None:
        self.pipeline = pipeline
        self.project = project
        self.run_root = run_root
        self.degraded: dict[str, str] = {}

    def _optional(self, name: str, action):
        """Run one inspection step, recording unavailability instead of aborting the probe.

        The Pipeline package is 0.4.0-exp.1: individual tools can be missing or change shape
        between versions, and losing one probe signal is not a reason to lose the frames.
        """
        try:
            return action()
        except PipelineError as error:
            self.degraded[name] = str(error)[:300]
            return None

    def require_boot_scene(self, boot_scene: str, source: str) -> dict:
        """Fail early and specifically when the Editor has no scene loaded.

        Without this the probe happily captures frame after frame of empty skybox and reports
        that the game rendered nothing, which reads as a game bug rather than a setup mistake.

        A *different* scene being loaded is reported, not fatal: it is legitimate during
        authoring, and the frames still say more than an aborted run would.
        """
        scenes = self.pipeline.call("list_open_scenes")
        loaded = [scene for scene in scenes.get("scenes", []) if scene.get("path")]
        if not loaded:
            raise ProbeFailure(
                "No scene is loaded in the Editor, so Play Mode would render an empty skybox and "
                f"nothing would boot. Open {boot_scene} first (resolved from {source})."
            )
        paths = [scene.get("path") for scene in loaded]
        return {
            "scenes": paths,
            "bootScene": boot_scene,
            "bootSceneSource": source,
            "bootSceneLoaded": boot_scene in paths,
        }

    def capture(self, label: str, inline: bool, max_resolution: int) -> dict:
        relative = f"Temp/probe-frames/{label}.png"
        absolute = self.project / relative
        absolute.parent.mkdir(parents=True, exist_ok=True)

        shot = self.pipeline.screenshot(relative, view="game")
        frame: dict = {"label": label, "path": shot.get("path") or str(absolute)}
        frame.update(describe_frame(Path(frame["path"])))

        if inline:
            payload = self._optional(
                "capture_game_view",
                lambda: self.pipeline.capture_inline(max_resolution=max_resolution),
            )
            if payload:
                # The tool returns the image under one of a couple of keys depending on whether
                # save_path was involved; keep whichever is actually populated.
                encoded = payload.get("base64") or payload.get("image") or ""
                if encoded:
                    frame["inlineBase64Bytes"] = len(encoded)
                    frame["inlinePng"] = encoded
        return frame

    def error_delta(self, seen: set[str]) -> dict:
        logs = self._optional(
            "get_console_logs",
            lambda: self.pipeline.console_logs(severity="Error", limit=100),
        )
        if logs is None:
            return {"available": False}
        entries = logs.get("logs") or logs.get("entries") or []
        fresh = []
        for entry in entries:
            message = entry.get("message") or entry.get("Message") or str(entry)
            key = message[:200]
            if key not in seen:
                seen.add(key)
                fresh.append(message[:400])
        return {"available": True, "newErrors": fresh, "newErrorCount": len(fresh)}

    @staticmethod
    def _unset_fields(fields: list) -> list[str]:
        """Names of serialized fields that read back as nothing.

        `get_serialized_fields` returns a list of {name, propertyType, value}. An object
        reference that failed to resolve comes back as a null value, which is precisely the
        footprint of a presenter that was instantiated but never configured. Numeric zero and
        `False` are deliberately NOT treated as unset — they are legitimate values, and folding
        them in here would drown the real signal in noise.
        """
        unset = []
        for field in fields:
            if not isinstance(field, dict):
                continue
            value = field.get("value")
            if value is None or value == "" or value == []:
                unset.append(str(field.get("name")))
        return sorted(unset)

    def probe_presenters(self, component: str, limit: int) -> dict:
        """Read serialized fields of the live objects carrying a given component.

        This is the only signal here that can catch the silent-serialization class: a presenter
        that was instantiated, joined the hierarchy and answers RPCs, but whose template data
        resolved to null and got swallowed by `?.`, so it was never configured. Nothing throws,
        so the flow tests cannot see it — but the field reads back null.
        """
        found = self._optional(
            "find_gameobjects",
            lambda: self.pipeline.find_gameobjects(type_name=component),
        )
        if found is None:
            return {"available": False}

        objects = found.get("gameObjects") or []
        probes = []
        for entry in objects[:limit]:
            handle = entry.get("globalId") or entry.get("hierarchyPath")
            if not handle:
                continue
            fields = self._optional(
                f"get_serialized_fields:{handle}",
                lambda handle=handle: self.pipeline.serialized_fields(str(handle), component=component),
            )
            if fields is None:
                continue
            values = fields.get("fields") or []
            probes.append(
                {
                    "target": str(handle),
                    "hierarchyPath": entry.get("hierarchyPath"),
                    "componentType": fields.get("type"),
                    "fieldCount": len(values),
                    "unsetFields": self._unset_fields(values),
                }
            )
        return {
            "available": True,
            "component": component,
            "matched": len(objects),
            "probes": probes,
        }

    def run(
        self,
        game_id: str,
        frames: int,
        interval: float,
        inline: bool,
        max_resolution: int,
        presenter_component: str | None,
        presenter_limit: int,
        bridge_extra: list[str],
        boot_scene: str,
        boot_scene_source: str,
    ) -> dict:
        self.pipeline.wait_until_ready()
        scene_info = self.require_boot_scene(boot_scene, boot_scene_source)

        # A previous probe leaves Play Mode running with a live match, and the bridge then refuses
        # the next start with "A match is already running". Clearing it here is what makes the
        # profile repeatable; without it every run after the first fails for a reason that has
        # nothing to do with the game under test.
        if self.pipeline.editor_status().get("playMode") != "stopped":
            self._optional("editor_stop", lambda: self.pipeline.call("editor_stop"))
            self.pipeline.wait_until_ready()

        # Without this the Editor stops advancing the match whenever it loses focus, and every
        # frame after the first looks identical for reasons that have nothing to do with the game.
        self._optional("set_autotick", lambda: self.pipeline.set_autotick(True))

        seen_errors: set[str] = set()
        self.error_delta(seen_errors)  # prime the baseline; pre-existing errors are not ours

        # A failed start-local is recorded, not fatal. Dobro proved why: its match rendered a full
        # board — five seated players, a dealt hand, the table deck — while `start_local_match`
        # timed out, because the tutorial flow was still up and the bridge's completion condition
        # never satisfied. Aborting here would have reported a perfectly healthy game as broken.
        # The frames are the evidence; the bridge's verdict is one input beside them.
        start = run_bridge_scenario(self.project, game_id, bridge_extra, timeout=600)
        bridge_start = {
            "exitCode": start["exitCode"],
            "ok": start["exitCode"] == 0,
            "scenarioStatus": (start.get("report") or {}).get("status"),
            "error": (start.get("report") or {}).get("error", "")[:600] or None,
        }

        captured = []
        for index in range(frames):
            if index:
                time.sleep(interval)
            captured.append(self.capture(f"{game_id}-{index:02d}", inline, max_resolution))

        errors = self.error_delta(seen_errors)
        presenters = (
            self.probe_presenters(presenter_component, presenter_limit)
            if presenter_component
            else {"skipped": True}
        )

        rendered = [frame for frame in captured if not frame.get("looksFlat", False) and frame.get("bytes")]
        flat = [frame["label"] for frame in captured if frame.get("looksFlat")]

        # Without Pillow the flat-frame test never runs, so "not flat" only means "not proven
        # flat". Saying "rendered" on that basis would be exactly the unverified pass this probe
        # exists to prevent, so the missing check is promoted into the verdict instead of being
        # left as a footnote nobody reads.
        unverified = [frame["label"] for frame in captured if "looksFlat" not in frame]

        if not rendered:
            verdict = "no-content"
        elif errors.get("newErrorCount"):
            verdict = "rendered-with-errors"
        elif unverified:
            verdict = "rendered-unverified"
        elif not bridge_start["ok"]:
            # Rendered fine, but the flow gate disagreed. Worth surfacing as its own verdict:
            # it is usually the bridge's wait condition (tutorial still up, non-standard phase),
            # not the game — but it should never be silently rounded down to "all good".
            verdict = "rendered-bridge-disagreed"
        else:
            verdict = "rendered"

        return {
            "schemaVersion": 1,
            "game": game_id,
            "verdict": verdict,
            "bridgeStart": bridge_start,
            "forwardedToBridge": bridge_extra,
            "scenes": scene_info["scenes"],
            "bootScene": scene_info["bootScene"],
            "bootSceneSource": scene_info["bootSceneSource"],
            "bootSceneLoaded": scene_info["bootSceneLoaded"],
            "frames": captured,
            "flatFrames": flat,
            "framesNotAnalysed": unverified,
            "frameAnalysisHint": (
                "Install Pillow (`python3 -m pip install --user Pillow`) to enable the flat-frame "
                "check that distinguishes a real frame from an empty skybox."
                if unverified
                else None
            ),
            "errors": errors,
            "presenters": presenters,
            "degraded": self.degraded,
            "provenValue": (
                "Frames rendered with real content. This does NOT prove the game is playable or "
                "the rules are correct — read the frames."
            ),
        }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("game_id")
    parser.add_argument("--project", default=None)
    parser.add_argument("--frames", type=int, default=3)
    parser.add_argument("--interval", type=float, default=4.0)
    parser.add_argument("--output", help="Write the JSON report here.")
    parser.add_argument(
        "--inline",
        action="store_true",
        help="Embed each frame as base64 in the report so a reader sees pixels, not paths.",
    )
    parser.add_argument("--max-resolution", type=int, default=384, help="Cap on inline frame longest edge.")
    parser.add_argument(
        "--presenter-component",
        default=None,
        help="Component type whose serialized fields to read, e.g. a presenter class name. "
        "find_gameobjects matches exact types only, so this is a type name, not a search query.",
    )
    parser.add_argument("--presenter-limit", type=int, default=8)
    parser.add_argument(
        "--boot-scene",
        default=None,
        help="Scene that must be loaded for the app to boot. Defaults to UNITY_BOOT_SCENE from "
        "the project's project-config.sh, then the first scene in its Build Settings.",
    )
    # Anything this parser does not recognise is forwarded to `run_bridge_scenarios.py start-local`
    # (e.g. --player-count 4 --teams 2,2). argparse.REMAINDER cannot be used for that: as a
    # positional it swallows this script's own flags too, which silently forwarded --frames and
    # --output to the bridge and made it exit on unrecognized arguments.
    return parser


def main(argv: list[str] | None = None) -> int:
    args, bridge_extra = build_parser().parse_known_args(argv)
    project = resolve_project_path(args.project)
    run_root = project / "Logs" / "runs"
    run_root.mkdir(parents=True, exist_ok=True)

    pipeline = Pipeline(project)
    probe = GameProbe(pipeline, project, run_root)

    bridge_extra = [token for token in bridge_extra if token != "--"]

    try:
        boot_scene, boot_scene_source = resolve_boot_scene(project, args.boot_scene)
    except ProbeFailure as error:
        _emit({"schemaVersion": 1, "game": args.game_id, "verdict": "error", "error": str(error)}, args.output)
        return 1

    try:
        report = probe.run(
            args.game_id,
            frames=args.frames,
            interval=args.interval,
            inline=args.inline,
            max_resolution=args.max_resolution,
            presenter_component=args.presenter_component,
            presenter_limit=args.presenter_limit,
            bridge_extra=bridge_extra,
            boot_scene=boot_scene,
            boot_scene_source=boot_scene_source,
        )
    except (ProbeFailure, PipelineError) as error:
        report = {"schemaVersion": 1, "game": args.game_id, "verdict": "error", "error": str(error)}
        _emit(report, args.output)
        return 1

    _emit(report, args.output)
    # "rendered-bridge-disagreed" is a pass with a caveat: the pixels are there. It stays
    # non-zero so a scripted gate still stops and looks, but it is not the same as no-content.
    return 0 if report["verdict"] == "rendered" else 1


def _emit(report: dict, output: str | None) -> None:
    if output:
        Path(output).parent.mkdir(parents=True, exist_ok=True)
        Path(output).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    # Inline frames make the stdout copy unreadable; the file keeps them, the console gets a digest.
    digest = json.loads(json.dumps(report))
    for frame in digest.get("frames", []):
        frame.pop("inlinePng", None)
    print(json.dumps(digest, indent=2))
    if output:
        print(f"\nreport: {output}", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
