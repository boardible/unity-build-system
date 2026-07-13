# Unity Dev Check

Use `dev-check.sh` as the default entry point for local and agent validation:

```bash
./Scripts/dev-check.sh compile
./Scripts/dev-check.sh game dobro
./Scripts/dev-check.sh finish sushiGo
./Scripts/dev-check.sh triage sushiGo
./Scripts/dev-check.sh full
```

## Choosing a profile

- `compile`: cheapest batchmode C# import/compile check.
- `game`: one game through load, start, cleanup, action, and progression. It
  enables fail-fast and does not run the completion gate.
- `finish`: only the slow bot completion gate for one game.
- `triage`: reuses an already-open Editor through the control bridge, avoiding
  Unity startup/import. It captures status, gameplay, exceptions, and a reliable
  Game View screenshot. Batchmode failure screenshots are best-effort and include
  a `screenshotQuality` marker because `-nographics` may produce an empty frame.
- `full`: aggregate smoke for broad confidence. It collects every failure unless
  `--fail-fast` is explicitly supplied.

Smoke options can be forwarded, for example:

```bash
./Scripts/dev-check.sh game dobro --phase action --phone-only
./Scripts/dev-check.sh full --games dobro,quartz,sushiGo --batch-size 2
./Scripts/dev-check.sh full --category SmokeRender
```

## Artifacts

Every batchmode check gets one run directory:

```text
Logs/runs/<run-id>/
  summary.txt
  summary.json
  main/ or batch-XX/
    unity.log
    results.xml
    events.ndjson
    summary.txt
    summary.json
    triage/                 # only populated on failure
      <game>/<phase>/
        diagnostics.json
        gameplay.json
        timeline.json
        screenshot.png
      signals.log
      manifest.json
```

Read `summary.json` first. It includes per-game/per-phase duration, stable failure
fingerprints, and artifact paths. Raw logs are fallback evidence.

Run directories are retained as a unit. The default is five runs and can be
changed with `UNITY_ARTIFACT_RETENTION` or cleaned immediately with:

```bash
./Scripts/pruneUnityArtifacts.sh --keep 3
```

`runSmokeTestsIsolated.sh` remains the cold-restart fallback for suspected state
leaks between games; it is intentionally not the normal fast path.

Without `--batch-size`, a smoke selection shares one Unity process. Batching
restarts Unity once per batch and should only be used to cap state leakage or
memory growth. The isolated runner restarts once per game and is the slowest,
strongest isolation mode.
