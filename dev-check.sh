#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/common.sh"

profile="${1:-}"
[[ $# -gt 0 ]] && shift
run_id="${DEV_CHECK_RUN_ID:-dev-${profile:-unknown}-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
run_root="$PROJECT_PATH/Logs/runs/$run_id"

usage() {
    cat <<'EOF'
Usage:
  ./Scripts/dev-check.sh compile [extra Unity args]
  ./Scripts/dev-check.sh tests [--filter <name-or-regex>] [extra Unity args]
  ./Scripts/dev-check.sh game <game-id> [smoke options]
  ./Scripts/dev-check.sh finish <game-id> [smoke options]
  ./Scripts/dev-check.sh visual <game-id> [smoke options]
  ./Scripts/dev-check.sh walkthrough <game-id> [--frames N] [--interval S] [--pause-at NAME]
  ./Scripts/dev-check.sh probe <game-id> [--frames N] [--interval S] [--presenter-query Q]
  ./Scripts/dev-check.sh debug-player [--output <dir>]
  ./Scripts/dev-check.sh triage <game-id> [bridge scenario options]
  ./Scripts/dev-check.sh full [smoke options]

Profiles:
  compile  Import/compile C# only; no Addressables or player build.
  tests    Full EditMode suite, including the serialized game-data integrity guards.
  game     One game through load/start/cleanup/action/human/progression; fail-fast.
  finish   One bot game through the dedicated completion gate; fail-fast.
  visual   Start one game with graphics and require a usable gameplay screenshot.
  walkthrough  Play a match in an open Editor, screenshotting each checkpoint into an HTML sheet.
  probe    Like walkthrough, but the report carries the frames inline for an agent to read
           directly instead of an HTML sheet a human has to open. Needs the Unity CLI.
  debug-player  Build a macOS development Player that the Unity CLI can drive (muted, agent
           capture enabled). WARNING: switching to StandaloneOSX reimports every asset, and
           switching back for an iOS/Android build reimports again.
  triage   Reuse an open Unity Editor through the bridge; no Unity restart.
  full     Full aggregate smoke; continues to collect all failures by default.

Set DEV_CHECK_RUN_ID to choose a stable run id.
EOF
}

require_game() {
    if [[ -z "${1:-}" ]]; then
        log_error "Profile '$profile' requires a game id."
        usage
        exit 1
    fi
}

run_compile() {
    load_project_config "$PROJECT_PATH/project-config.sh" >/dev/null 2>&1 || true
    local version="${UNITY_VERSION:-$(detect_unity_version "$PROJECT_PATH")}"
    local unity_path="${UNITY_PATH:-$(find_unity_path "$version")}"
    local log_file="$run_root/unity.log"

    if [[ -z "$unity_path" || ! -f "$unity_path" ]]; then
        log_error "Unity $version was not found."
        exit 1
    fi
    if pgrep -af "Unity.app/Contents/MacOS/Unity" | grep -q -- "-projectPath $PROJECT_PATH"; then
        log_error "The project is already open in Unity. Let the Editor finish compiling or use the triage profile."
        exit 1
    fi

    mkdir -p "$run_root"
    append_unity_launch_args
    set +e
    "$unity_path" -batchmode -nographics ${UNITY_LAUNCH_ARGS_RESULT[@]+"${UNITY_LAUNCH_ARGS_RESULT[@]}"} \
        -projectPath "$PROJECT_PATH" -executeMethod BuildScript.QuickCompile \
        -stackTraceLogType Full -logFile "$log_file" "$@"
    local exit_code=$?
    set -e

    python3 - "$run_id" "$exit_code" "$log_file" "$run_root/summary.json" <<'PY'
import json, sys
run_id, exit_code, log_path, output = sys.argv[1:]
payload = {"schemaVersion": 1, "runId": run_id, "profile": "compile", "status": "passed" if exit_code == "0" else "failed", "exitCode": int(exit_code), "artifacts": {"log": log_path}}
open(output, "w", encoding="utf-8").write(json.dumps(payload, indent=2) + "\n")
PY
    log "Run: $run_root"
    return "$exit_code"
}

# EditMode tests had no entry point in this ladder at all, so the whole Assets/Tests/EditMode suite
# had never been executed by any automation — not here, not in CI (main.yml only builds and deploys).
# `compile` cannot stand in for it either: it does not define UNITY_INCLUDE_TESTS, so the test
# assemblies are not even compiled by it.
run_edit_tests() {
    load_project_config "$PROJECT_PATH/project-config.sh" >/dev/null 2>&1 || true
    local version="${UNITY_VERSION:-$(detect_unity_version "$PROJECT_PATH")}"
    local unity_path="${UNITY_PATH:-$(find_unity_path "$version")}"
    local log_file="$run_root/unity.log"
    local results_file="$run_root/editmode-results.xml"

    if [[ -z "$unity_path" || ! -f "$unity_path" ]]; then
        log_error "Unity $version was not found."
        exit 1
    fi
    if pgrep -af "Unity.app/Contents/MacOS/Unity" | grep -q -- "-projectPath $PROJECT_PATH"; then
        log_error "The project is already open in Unity. Close the Editor before running the test suite."
        exit 1
    fi

    local filter_args=()
    if [[ -n "${1:-}" && "$1" == "--filter" ]]; then
        [[ -z "${2:-}" ]] && { log_error "--filter needs a value."; exit 1; }
        filter_args=(-testFilter "$2")
        shift 2
    fi

    mkdir -p "$run_root"
    append_unity_launch_args
    set +e
    "$unity_path" -batchmode -nographics ${UNITY_LAUNCH_ARGS_RESULT[@]+"${UNITY_LAUNCH_ARGS_RESULT[@]}"} \
        -projectPath "$PROJECT_PATH" \
        -runTests -testPlatform EditMode -testResults "$results_file" \
        ${filter_args[@]+"${filter_args[@]}"} \
        -stackTraceLogType Full -logFile "$log_file" "$@"
    local exit_code=$?
    set -e

    # The summarizer exits non-zero to report test failures, which `set -e` would turn into an abort
    # before the status can be captured or the run path logged.
    set +e
    python3 "$SCRIPT_DIR/summarize_edit_tests.py" \
        --run-id "$run_id" --exit-code "$exit_code" \
        --results "$results_file" --log "$log_file" \
        --json "$run_root/summary.json" --text "$run_root/summary.txt"
    local summary_code=$?
    set -e

    log "Run: $run_root"
    # A crashed Unity leaves no XML, so the launcher's own status still has to count.
    if [[ "$exit_code" -ne 0 ]]; then return "$exit_code"; fi
    return "$summary_code"
}

mkdir -p "$run_root"
prune_unity_artifacts "$PROJECT_PATH"

case "$profile" in
    compile)
        run_compile "$@"
        ;;
    tests)
        run_edit_tests "$@"
        ;;
    game)
        require_game "${1:-}"
        game_id="$1"
        shift
        exec "$SCRIPT_DIR/runSmokeTests.sh" --run-id "$run_id" --games "$game_id" --fail-fast "$@"
        ;;
    finish)
        require_game "${1:-}"
        game_id="$1"
        shift
        exec "$SCRIPT_DIR/runSmokeTests.sh" --run-id "$run_id" --phase finish --auto-finish-games "$game_id" --fail-fast "$@"
        ;;
    visual)
        require_game "${1:-}"
        game_id="$1"
        shift
        exec "$SCRIPT_DIR/runSmokeTests.sh" --run-id "$run_id" --phase all --games "$game_id" --graphics --fail-fast "$@"
        ;;
    walkthrough)
        require_game "${1:-}"
        game_id="$1"
        shift
        set +e
        # 30s (the runner default) is not enough: entering Play Mode runs the whole boot sequence and
        # routinely takes longer, which reads as a bridge timeout even though it succeeded.
        python3 "$SCRIPT_DIR/run_bridge_scenarios.py" --project "$PROJECT_PATH" \
            --timeout 180 --wait-timeout 420 \
            --output "$run_root/walkthrough.json" --artifact-prefix "$run_id-" --quiet \
            walkthrough "$game_id" --report "$run_root/walkthrough.html" "$@"
        exit_code=$?
        set -e
        log "Report: $run_root/walkthrough.html"
        exit "$exit_code"
        ;;
    probe)
        require_game "${1:-}"
        game_id="$1"
        shift
        if ! command -v unity >/dev/null 2>&1; then
            log_error "The 'unity' CLI is not on PATH. Install it with 'brew update && brew install --cask unity-cli'."
            exit 1
        fi
        # Exports UNITY_BOOT_SCENE, which the probe needs: the three projects disagree on the
        # boot scene path, so shared Scripts/ code cannot default it.
        load_project_config "$PROJECT_PATH/project-config.sh" >/dev/null 2>&1 || true
        set +e
        UNITY_BOOT_SCENE="${UNITY_BOOT_SCENE:-}" \
        python3 "$SCRIPT_DIR/probe_game_visuals.py" "$game_id" \
            --project "$PROJECT_PATH" --inline \
            --output "$run_root/probe.json" "$@"
        exit_code=$?
        set -e
        log "Report: $run_root/probe.json"
        exit "$exit_code"
        ;;
    debug-player)
        if ! command -v unity >/dev/null 2>&1; then
            log_error "The 'unity' CLI is not on PATH. Install it with 'brew update && brew install --cask unity-cli'."
            exit 1
        fi
        if pgrep -af "Unity.app/Contents/MacOS/Unity" | grep -q -- "-projectPath $PROJECT_PATH"; then
            log_error "The project is open in Unity. Close the Editor first — this build runs in batchmode."
            exit 1
        fi
        output="${2:-$PROJECT_PATH/Builds/DebugPlayer}"
        log "Building a macOS development Player. The first StandaloneOSX switch reimports every asset."
        set +e
        unity build "$PROJECT_PATH" \
            --target StandaloneOSX \
            --execute-method BuildDebugPlayer.BuildOSX \
            --output-path "$output" \
            --log-file "$run_root/build.log"
        exit_code=$?
        set -e
        log "Log: $run_root/build.log"
        if [ "$exit_code" -eq 0 ]; then
            log "Player: $output/BoardibleDebug.app"
            log "Run it, then attach with: unity command --runtime BoardibleDebug runtime_status"
        fi
        exit "$exit_code"
        ;;
    triage)
        require_game "${1:-}"
        game_id="$1"
        shift
        set +e
        python3 "$SCRIPT_DIR/run_bridge_scenarios.py" --project "$PROJECT_PATH" \
            --output "$run_root/triage.json" --artifact-prefix "$run_id-" --quiet start-local "$game_id" "$@"
        exit_code=$?
        set -e
        log "Run: $run_root"
        exit "$exit_code"
        ;;
    full)
        exec "$SCRIPT_DIR/runSmokeTests.sh" --run-id "$run_id" --phase all "$@"
        ;;
    help|-h|--help|"")
        usage
        ;;
    *)
        log_error "Unknown dev-check profile: $profile"
        usage
        exit 1
        ;;
esac
