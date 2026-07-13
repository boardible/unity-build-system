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
  ./Scripts/dev-check.sh game <game-id> [smoke options]
  ./Scripts/dev-check.sh finish <game-id> [smoke options]
  ./Scripts/dev-check.sh triage <game-id> [bridge scenario options]
  ./Scripts/dev-check.sh full [smoke options]

Profiles:
  compile  Import/compile C# only; no Addressables or player build.
  game     One game through load/start/cleanup/action/progression; fail-fast.
  finish   One bot game through the dedicated completion gate; fail-fast.
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

mkdir -p "$run_root"
prune_unity_artifacts "$PROJECT_PATH"

case "$profile" in
    compile)
        run_compile "$@"
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
