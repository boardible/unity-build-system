#!/bin/bash

set -e

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/lib/common.sh"

print_banner "Unity GameDoctor"

GAME_DOCTOR_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --game|--games)
            GAME_DOCTOR_ARGS+=("$1" "$2")
            shift 2
            ;;
        --all|--fix|--no-fail|--verbose)
            GAME_DOCTOR_ARGS+=("$1")
            shift
            ;;
        --report)
            GAME_DOCTOR_ARGS+=("$1" "$2")
            shift 2
            ;;
        --help)
            echo "Usage: ./Scripts/runGameDoctor.sh [options]"
            echo ""
            echo "Options:"
            echo "  --game <id>        Validate one game id"
            echo "  --games <csv>      Validate a comma-separated list of game ids"
            echo "  --all              Validate all games (default)"
            echo "  --fix              Remove safe null list entries while reporting issues"
            echo "  --report <path>    Output JSON report path (default: Logs/game-doctor.json)"
            echo "  --no-fail          Exit 0 even if GameDoctor reports errors"
            echo "  --verbose          Log clean game summaries too"
            echo "  --help             Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

load_project_config "$PROJECT_PATH/project-config.sh" || true

if [ -z "$UNITY_VERSION" ]; then
    DETECTED_VERSION=$(detect_unity_version "$PROJECT_PATH")
    if [ -n "$DETECTED_VERSION" ]; then
        export UNITY_VERSION="$DETECTED_VERSION"
    else
        export UNITY_VERSION="6000.3.17f1"
    fi
fi

UNITY_PATH=$(find_unity_path "$UNITY_VERSION")
if [ -z "$UNITY_PATH" ]; then
    log_error "Unity $UNITY_VERSION not found."
    exit 1
fi

ensure_project_not_open_in_unity() {
    local unity_processes
    unity_processes=$(pgrep -af "Unity.app/Contents/MacOS/Unity" | grep -- "-projectPath $PROJECT_PATH" || true)

    if [ -n "$unity_processes" ]; then
        log_error "Another Unity instance already has this project open:"
        echo "$unity_processes"
        exit 1
    fi
}

run_unity_with_followed_log() {
    local log_file="$1"
    shift

    : > "$log_file"

    tail -n +1 -F "$log_file" > >(grep --line-buffered -E "\[GameDoctor\]|Error |Exception|Failed|Completed") &
    local tail_pid=$!

    set +e
    "$@" -logFile "$log_file"
    local exit_code=$?
    set -e

    kill "$tail_pid" >/dev/null 2>&1 || true
    wait "$tail_pid" 2>/dev/null || true

    return $exit_code
}

LOGS_PATH="$PROJECT_PATH/Logs"
mkdir -p "$LOGS_PATH"
prune_unity_artifacts "$PROJECT_PATH"

log "Project Path: $PROJECT_PATH"
log "Unity Path: $UNITY_PATH"
ensure_project_not_open_in_unity
append_unity_launch_args

log_file="$LOGS_PATH/unity-gamedoctor-$(date +%Y%m%d-%H%M%S).log"
run_unity_with_followed_log "$log_file" \
    "$UNITY_PATH" -batchmode -nographics "${UNITY_LAUNCH_ARGS_RESULT[@]}" \
    -projectPath "$PROJECT_PATH" \
    -executeMethod "BuildScript.RunGameDoctor" \
    -stackTraceLogType Full \
    "${GAME_DOCTOR_ARGS[@]}"
exit_code=$?

if [ $exit_code -eq 0 ]; then
    log_success "GameDoctor completed successfully"
else
    log_error "GameDoctor failed with exit code $exit_code"
    log_error "Check log file: $log_file"
    tail -40 "$log_file" 2>/dev/null || true
    exit $exit_code
fi

log "Log file: $log_file"
