# Unity Control Bridge

This script talks to the local Unity Editor bridge through `.utmp/unity-control-bridge` inside each project.

## Location

- Client: `Scripts/unity_control_bridge.py`
- Bridge state: `<project>/.utmp/unity-control-bridge/`

## Examples

```bash
python3 Scripts/unity_control_bridge.py --project boardgames heartbeat
python3 Scripts/unity_control_bridge.py --project boardgames status
python3 Scripts/unity_control_bridge.py --project boardgames open-game dobro --target builder
python3 Scripts/unity_control_bridge.py --project boardgames start-local dobro --player-count 4 --teams 2,2
python3 Scripts/unity_control_bridge.py --project boardgames rpc playCard PieceRpcData '{"pieceId":"abc"}'
python3 Scripts/unity_control_bridge.py --project boardgames menu 'Boardible/Doctor/Run All Steps'
python3 Scripts/unity_control_bridge.py --project boardgames screenshot --file-name boardgames-debug.png
python3 Scripts/run_bridge_scenarios.py --project boardgames baseline
python3 Scripts/run_bridge_scenarios.py --project boardgames onboarding-reset
python3 Scripts/run_bridge_scenarios.py --project boardgames open-game dobro --target lobby
python3 Scripts/run_bridge_scenarios.py --project boardgames start-local dobro --player-count 4 --teams 2,2
```

## Commands

- `heartbeat`
- `status`
- `exceptions`
- `open-game`
- `start-local`
- `menu`
- `screenshot`
- `debug`
- `rpc`
- `enter-play`
- `exit-play`
- `raw`

## Scenario Runner

`Scripts/run_bridge_scenarios.py` wraps the low-level bridge commands into reusable runtime checks with evidence output.

Initial scenarios:

- `baseline` — verifies heartbeat/capabilities, enters Play Mode if needed, collects status, recent exceptions, and a screenshot.
- `onboarding-reset` — runs `OnboardingPlayModeHarness.ResetToFreshOnboarding`, then proves onboarding is reachable via `OnboUIScreen.DebugGetStepIndex`.
- `open-game <game_id>` — opens a game through the bridge and waits until the room snapshot reflects that game.
- `start-local <game_id>` — starts a local match and waits until the game controller snapshot reflects that game.

Useful options:

- `--output <path>` — saves the JSON report to disk.
- `--allow-exceptions` — keeps the scenario green even if the bridge reports recent exceptions.
- `--skip-screenshot` — skips screenshot capture when the run should avoid the timing-sensitive screenshot path.
- `--wait-timeout <seconds>` — extends polling waits for slow editor boots.
- `--poll-interval <seconds>` — controls status polling cadence.

## Notes

- `open-game --target builder` uses Board Builder when available.
- `start-local` writes quick play settings before entering Play Mode.
- `rpc` expects a valid `GameRpcData` subtype plus a JSON object payload.
- Screenshots are written to `<project>/.utmp/unity-control-bridge/screenshots/`.