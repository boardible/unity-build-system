#!/usr/bin/env python3
"""Look at a game running in a real Player, not the Editor.

Why a Player
------------
The Editor is the heaviest process on a dev machine and was killed five times in one session under
memory pressure on a 16GB host; a Player is a fraction of that. It is also the only place
`capture_frame_raw` fully pays off — in the Editor the same call returns the Game View *window*,
chrome and all ("Game / Display 1 / Free Aspect"), while a Player has no chrome to include.

What this checks, and what it deliberately does not
---------------------------------------------------
It brings the Player to a running match of one game, lets the opening animations actually play, and
captures frames. It does NOT play the match out. The question here is "does this game come up and
look right", which a whole match does not answer any better than the first ten seconds — the smoke
suite already owns "do the rules work".

Animations are allowed to run at full speed on purpose. `GamePacing` only collapses presentation
waits when there is no graphics device; a Player has one, so what is captured is what a player would
see. Making this lane fast by skipping animations would mean photographing frames of animations that
never played.

Requires
--------
- A development Player built by `BuildDebugPlayer.BuildOSX` (development build is not optional: the
  Pipeline runtime server is compiled out of a release build entirely).
- `Assets/App/DevTools/GameControlCommands.cs`, which is what makes a Player able to be told which
  game to open — the Editor control bridge cannot: it is driven by `EditorApplication.update`.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from unity_pipeline import Pipeline, PipelineError, resolve_project_path  # noqa: E402

DEFAULT_APP = "Builds/DebugPlayer/BoardibleDebug.app"
PORT_FILE = ".unity-pipeline-runtime-port"


class PlayerProbeFailure(RuntimeError):
    pass


def launch_player(app: Path, extra_args: list[str]) -> subprocess.Popen | None:
    """Start the Player detached from this shell.

    `open -na` rather than Popen/nohup: a process started from a tool shell gets reaped when the
    shell's process group is cleaned up, which kills the Player mid-run and looks exactly like a
    crash. `open` hands it to launchd instead.
    """
    if not app.exists():
        raise PlayerProbeFailure(
            f"No Player at {app}. Build one first:\n"
            f"  unity build --target StandaloneOSX --execute-method BuildDebugPlayer.BuildOSX\n"
            f"Note this switches the active build target and reimports every asset."
        )
    subprocess.run(["open", "-na", str(app), "--args", *extra_args], check=True)
    return None


def find_port_file(app: Path) -> Path | None:
    """Locate the descriptor the runtime server writes, so we attach to *this* Player.

    Matching by process name works until a second Player of the same build is up, at which point it
    is a coin flip. The descriptor names one instance.
    """
    candidates = [
        Path.home() / "Library" / "Application Support",
        app.parent,
    ]
    newest = None
    for root in candidates:
        if not root.exists():
            continue
        for found in root.rglob(PORT_FILE):
            if newest is None or found.stat().st_mtime > newest.stat().st_mtime:
                newest = found
    return newest


def wait_for_server(pipeline: Pipeline, timeout: float) -> dict:
    """Poll until the Player's command surface answers.

    A Player boots Addressables and the whole app before the server is useful, so the first several
    attempts failing is normal and not worth reporting as an error.
    """
    deadline = time.time() + timeout
    last_error = "never attempted"
    while time.time() < deadline:
        try:
            status = pipeline.call("game_status")
            if status:
                return status
        except PipelineError as error:
            last_error = str(error)[:200]
        time.sleep(2)
    raise PlayerProbeFailure(
        f"The Player's pipeline server never answered within {timeout:.0f}s. Last error: {last_error}. "
        "A release build has the server compiled out — check the build was made with "
        "BuildOptions.Development."
    )


def wait_for_boot(pipeline: Pipeline, timeout: float) -> dict:
    """Wait for AppCore.Connection, which `start_local_match` needs.

    Not cosmetic: `AppRoom.HandleChangeGame` throws on a null gameSetup if called before the app has
    finished booting, and that NRE reads like a broken game rather than a premature call.
    """
    deadline = time.time() + timeout
    status = {}
    while time.time() < deadline:
        status = pipeline.call("game_status") or {}
        if status.get("appCoreConnection"):
            return status
        time.sleep(2)
    raise PlayerProbeFailure(f"The app never finished booting. Last status: {json.dumps(status)}")


def capture(pipeline: Pipeline, project: Path, label: str, out_dir: Path) -> dict:
    raw = out_dir / f"{label}.raw"
    result = pipeline.call("capture_frame_raw", output=str(raw))
    meta = result.get("metaPath")
    if not meta:
        return {"label": label, "error": "capture_frame_raw returned no sidecar", "raw": result}

    png = out_dir / f"{label}.png"
    converted = subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "raw_frame_to_png.py"), meta, "--output", str(png)],
        capture_output=True,
        text=True,
    )
    frame = {
        "label": label,
        "png": str(png) if png.exists() else None,
        "width": result.get("width"),
        "height": result.get("height"),
        "bytes": result.get("bytes"),
    }
    if converted.returncode != 0:
        frame["convertError"] = converted.stderr.strip()[:300]
    else:
        # The converter reports colour diversity; a frame of one flat colour is the empty-scene
        # signature and must not be reported as "it rendered".
        try:
            frame["analysis"] = json.loads(converted.stdout)
        except json.JSONDecodeError:
            frame["analysisText"] = converted.stdout.strip()[:300]
    return frame


def probe(args: argparse.Namespace) -> dict:
    project = resolve_project_path(args.project)
    app = Path(args.app) if Path(args.app).is_absolute() else project / args.app
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    launch_player(app, ["-unmute"] if args.unmute else [])
    time.sleep(args.launch_grace)

    port_file = find_port_file(app)
    pipeline = Pipeline(
        project,
        timeout=args.timeout,
        runtime=None if port_file else args.runtime_name,
        runtime_path=str(port_file) if port_file else None,
    )

    report: dict = {
        "schemaVersion": 1,
        "game": args.game_id,
        "app": str(app),
        "portFile": str(port_file) if port_file else None,
        "runtimeName": args.runtime_name,
    }

    try:
        report["serverStatus"] = wait_for_server(pipeline, args.server_timeout)
        report["bootStatus"] = wait_for_boot(pipeline, args.boot_timeout)

        started = pipeline.call(
            "start_local_match",
            gameId=args.game_id,
            **({"playerCount": args.player_count} if args.player_count else {}),
        )
        report["startLocalMatch"] = started

        frames = []
        for index in range(args.frames):
            # Animations run at full speed here by design, so the interval is what decides whether
            # distinct moments get photographed or the same held pose several times.
            time.sleep(args.interval)
            frames.append(capture(pipeline, project, f"{args.game_id}-{index:02d}", out_dir))
        report["frames"] = frames

        usable = [f for f in frames if f.get("png")]
        report["verdict"] = "captured" if usable else "no-frames"
    finally:
        if not args.keep_player:
            try:
                pipeline.call("quit")
            except PipelineError:
                # A Player that will not quit on request is a nuisance, not a probe failure — the
                # frames, if any, are already on disk.
                report["quit"] = "refused"

    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game_id")
    parser.add_argument("--project")
    parser.add_argument("--app", default=DEFAULT_APP)
    parser.add_argument("--runtime-name", default="BoardibleDebug")
    parser.add_argument("--output-dir", default="Logs/player-probe")
    parser.add_argument("--frames", type=int, default=4)
    parser.add_argument("--interval", type=float, default=3.0)
    parser.add_argument("--player-count", type=int, default=0)
    parser.add_argument("--launch-grace", type=float, default=5.0)
    parser.add_argument("--server-timeout", type=float, default=120.0)
    parser.add_argument("--boot-timeout", type=float, default=180.0)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--unmute", action="store_true")
    parser.add_argument("--keep-player", action="store_true", help="Leave the Player running.")
    parser.add_argument("--output", help="Write the JSON report here.")
    args = parser.parse_args(argv)

    try:
        report = probe(args)
    except (PlayerProbeFailure, PipelineError, subprocess.SubprocessError) as error:
        report = {"schemaVersion": 1, "game": args.game_id, "verdict": "error", "error": str(error)}

    payload = json.dumps(report, indent=2)
    if args.output:
        Path(args.output).write_text(payload)
    print(payload)
    return 0 if report.get("verdict") == "captured" else 1


if __name__ == "__main__":
    raise SystemExit(main())
