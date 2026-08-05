# Unity Dev Check

Use `dev-check.sh` as the default entry point for local and agent validation:

```bash
./Scripts/dev-check.sh compile
./Scripts/dev-check.sh game dobro
./Scripts/dev-check.sh finish sushiGo
./Scripts/dev-check.sh visual dobro
./Scripts/dev-check.sh probe dobro
./Scripts/dev-check.sh triage sushiGo
./Scripts/dev-check.sh full
```

## Choosing a profile

- `compile`: cheapest batchmode C# import/compile check.
- `game`: one game through load, start, cleanup, action, and progression. It
  enables fail-fast and does not run the completion gate.
- `finish`: only the slow bot completion gate for one game.
- `visual`: runs one game's correctness gates with a graphics device and captures
  start, first progression, and results evidence when its deterministic driver is
  complete. It fails when required images are empty or too small for review.
- `probe`: same idea as `walkthrough`, but the report carries each frame **inline**
  (base64) so whoever reads the JSON sees pixels, instead of a path to an HTML sheet
  someone has to open. Requires an open Editor with `GameBoxScene` loaded, plus the
  Unity CLI and its Pipeline package (see "Unity CLI probe" below).
- `triage`: reuses an already-open Editor through the control bridge, avoiding
  Unity startup/import. It captures status, gameplay, exceptions, and a reliable
  Game View screenshot. Batchmode failure screenshots are best-effort and include
  a `screenshotQuality` marker because `-nographics` may produce an empty frame.
- `full`: broad smoke with one fresh Unity process per game. It includes the
  completion gate for every game that declares a deterministic bot driver and
  collects every isolated failure unless `--fail-fast` is explicitly supplied.

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
  main/, game-<id>/, or batch-XX/
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

The ordinary correctness lanes remain headless. Use `visual` for a reviewable
gameplay screenshot, or append `--graphics` to `finish` to require both gameplay
and results screenshots for games with deterministic completion drivers.

Run directories are retained as a unit. The default is five runs and can be
changed with `UNITY_ARTIFACT_RETENTION` or cleaned immediately with:

```bash
./Scripts/pruneUnityArtifacts.sh --keep 3
```

The default `full` profile is the correctness baseline: each game owns a fresh
Unity process, so an uncooperative timeout cannot contaminate the next game.
`runSmokeTestsIsolated.sh` remains useful when a single custom test filter needs
the same cold-start behavior.

Supplying `--batch-size` opts into several games per process and restarts Unity
once per batch. Use that mode deliberately for the smaller sequential lifecycle
regression or for faster exploratory runs; it is not the isolated baseline.
Game-scoped phases (`load`, `start`, `lifecycle`, `cleanup`, `action`, `progression`,
`performance`, and requested `finish` games) also default to one process per
game. `safety` and `systems` run once. Supplying `--batch-size` is the explicit
opt-in to shared-process execution.

`--phase finish` requires `--auto-finish-games <csv>` and fails immediately when
the selection is missing. This prevents an empty completion suite from looking
green. The `full` profile supplies each isolated game automatically.

## Unity CLI probe

`probe` is the one lane whose verdict does not need a human to look at a contact sheet.
It exists because smoke proves flow, RPCs and scoring while proving nothing about the
screen — the failure mode that had BDB_Cards and LeTruc reported done on 8/8 while being
visually unplayable.

### Setup (once per machine, once per project)

```bash
brew update && brew install --cask unity-cli   # `brew update` first: a stale cask index hides it
unity auth login
unity pipeline install --project-path "$(pwd)"  # adds com.unity.pipeline to Packages/manifest.json
unity pipeline list                             # expect Server Reachable = true on port 7800
```

The Editor must be **open** with `Assets/App/Scenes/GameBoxScene.unity` loaded. A freshly
opened Editor sitting on an untitled scene renders an empty skybox and boots nothing, so the
probe checks for a loaded scene up front and fails with that specific reason rather than
capturing blank frames.

Optional: `python3 -m pip install --user Pillow`. Without it the flat-frame check cannot run,
so the probe reports `rendered-unverified` instead of `rendered` — it will not claim a frame
had real content when it could not measure that.

### Reading the verdict

| verdict | meaning |
|---|---|
| `rendered` | frames had real content, no new errors, and the bridge agreed the match started |
| `rendered-unverified` | frames look non-empty but Pillow is missing, so flatness was never measured |
| `rendered-bridge-disagreed` | pixels are there, but `start_local_match` did not satisfy its wait condition. Usually the bridge's condition, not the game — dobro renders a full board while timing out because its tutorial flow is still up |
| `rendered-with-errors` | frames rendered and new errors appeared; read `errors.newErrors` |
| `no-content` | nothing usable rendered. This is the real failure |
| `error` | the probe could not run at all; read `error` |

Only `rendered` exits 0. Everything else exits non-zero on purpose, so a scripted gate stops
and someone looks.

### Catching the unconfigured-presenter class

`--presenter-component <TypeName>` reads the serialized fields of every live object carrying
that component and lists the ones that came back null. That is the only signal in this repo
that can see the canonical silent failure — a presenter that was instantiated, joined the
hierarchy and answers RPCs, but whose template data resolved to null and was swallowed by
`?.`, so it was never configured. Nothing throws, so no behavioural test can catch it.

```bash
./Scripts/dev-check.sh probe dobro --frames 4 --interval 5 \
    --presenter-component DobroCardPresenter
```

Numeric zero and `false` are deliberately not counted as unset; only null / empty-string /
empty-array are, because folding in legitimate zeros buries the real signal.

### What it deliberately does not do

`run_tests` through the Pipeline package is **refused** by `Scripts/unity_pipeline.py`. Async
runs lose their results to the domain reload they trigger, sync runs hit a 30s server-side cap
the EditMode suite blows through, and a cancelled run leaves the framework throwing `Test tree
is not available for PostbuildCleanupWithTestDataTask` on every later attempt. Run EditMode
tests the existing way — `./Scripts/dev-check.sh tests`, Editor closed.

Both the CLI (`1.0.0-beta.3`) and the Pipeline package (`0.4.0-exp.1`) are pre-release. Keep
them out of the release path and CI until they are not.
