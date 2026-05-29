#!/bin/bash

set -e

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/lib/common.sh"

print_banner "Unity Smoke PlayMode Tests (Isolated)"

FILTER="SmokePlayModeTests.StartsLocalPlayForSupportedGames"
SMOKE_GAMES=""
RESULTS_DIR=""
PHONE_ONLY="false"
PER_GAME_TIMEOUT_SECONDS="240"
POST_RESULTS_GRACE_SECONDS="10"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --games)
            SMOKE_GAMES="$2"
            shift 2
            ;;
        --filter)
            FILTER="$2"
            shift 2
            ;;
        --results-dir)
            RESULTS_DIR="$2"
            shift 2
            ;;
        --timeout-seconds)
            PER_GAME_TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        --post-results-grace-seconds)
            POST_RESULTS_GRACE_SECONDS="$2"
            shift 2
            ;;
        --phone-only)
            PHONE_ONLY="true"
            shift
            ;;
        --help)
            echo "Usage: ./Scripts/runSmokeTestsIsolated.sh [options]"
            echo ""
            echo "Options:"
            echo "  --games <csv>                     Required comma-separated game ids"
            echo "  --filter <name>                   Unity test filter (default: SmokePlayModeTests.StartsLocalPlayForSupportedGames)"
            echo "  --results-dir <path>              Directory for per-game NUnit XML files (default: Logs/smoke-isolated-<timestamp>)"
            echo "  --timeout-seconds <n>             Max seconds to wait per game before killing Unity (default: 240)"
            echo "  --post-results-grace-seconds <n>  Seconds to allow Unity to exit after XML is written before killing it (default: 10)"
            echo "  --phone-only                      Skip TV navigation paths during smoke execution"
            echo "  --help                            Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ -z "$SMOKE_GAMES" ]; then
    log_error "--games is required."
    exit 1
fi

if ! [[ "$PER_GAME_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || [ "$PER_GAME_TIMEOUT_SECONDS" -le 0 ]; then
    log_error "Invalid value for --timeout-seconds: $PER_GAME_TIMEOUT_SECONDS. Use a positive integer."
    exit 1
fi

if ! [[ "$POST_RESULTS_GRACE_SECONDS" =~ ^[0-9]+$ ]] || [ "$POST_RESULTS_GRACE_SECONDS" -lt 0 ]; then
    log_error "Invalid value for --post-results-grace-seconds: $POST_RESULTS_GRACE_SECONDS. Use zero or a positive integer."
    exit 1
fi

load_project_config "$PROJECT_PATH/project-config.sh" || true

if [ -z "$UNITY_VERSION" ]; then
    DETECTED_VERSION=$(detect_unity_version "$PROJECT_PATH")
    if [ -n "$DETECTED_VERSION" ]; then
        export UNITY_VERSION="$DETECTED_VERSION"
    else
        export UNITY_VERSION="6000.3.16f1"
    fi
fi

UNITY_PATH=$(find_unity_path "$UNITY_VERSION")
if [ -z "$UNITY_PATH" ]; then
    log_error "Unity $UNITY_VERSION not found."
    exit 1
fi

cleanup_scene_recovery_artifacts() {
    local backup_dir="$PROJECT_PATH/Temp/__Backupscenes"
    local recovery_dir="$PROJECT_PATH/Assets/_Recovery"

    if [ -d "$backup_dir" ]; then
        rm -rf "$backup_dir"
        log_warn "Removed stale Unity scene backups from Temp/__Backupscenes"
    fi

    if [ -d "$recovery_dir" ]; then
        rm -rf "$recovery_dir"
        log_warn "Removed stale Unity recovery copies from Assets/_Recovery"
    fi
}

split_csv_into_array() {
    local csv="$1"
    local out_var="$2"
    local item
    local raw_items

    eval "$out_var=()"
    IFS=',' read -r -a raw_items <<< "$csv"
    for item in "${raw_items[@]}"; do
        item="${item#${item%%[![:space:]]*}}"
        item="${item%${item##*[![:space:]]}}"
        if [ -n "$item" ]; then
            eval "$out_var+=(\"\$item\")"
        fi
    done
}

wait_for_results_or_exit() {
    local pid="$1"
    local results_path="$2"
    local game_id="$3"
    local log_file="$4"
    local start_time="$(date +%s)"
    local results_seen_at=""

    while true; do
        if [ -f "$results_path" ] && grep -q '</test-run>' "$results_path" 2>/dev/null; then
            if [ -z "$results_seen_at" ]; then
                results_seen_at="$(date +%s)"
                log "[$game_id] Results file detected: $results_path"
            fi

            if ! kill -0 "$pid" 2>/dev/null; then
                return 0
            fi

            if [ $(( $(date +%s) - results_seen_at )) -ge "$POST_RESULTS_GRACE_SECONDS" ]; then
                log_warn "[$game_id] Unity still alive after writing results; terminating lingering process $pid"
                kill "$pid" 2>/dev/null || true
                for _ in 1 2 3 4 5; do
                    if ! kill -0 "$pid" 2>/dev/null; then
                        return 0
                    fi
                    sleep 1
                done
                kill -9 "$pid" 2>/dev/null || true
                return 0
            fi
        elif ! kill -0 "$pid" 2>/dev/null; then
            return 0
        fi

        if [ $(( $(date +%s) - start_time )) -ge "$PER_GAME_TIMEOUT_SECONDS" ]; then
            log_error "[$game_id] Timed out after ${PER_GAME_TIMEOUT_SECONDS}s waiting for smoke results"
            report_failure_classification "$game_id" "$log_file"
            kill "$pid" 2>/dev/null || true
            sleep 2
            kill -9 "$pid" 2>/dev/null || true
            return 1
        fi

        sleep 1
    done
}

read_test_result() {
    local results_path="$1"

    if [ ! -f "$results_path" ]; then
        printf 'missing'
        return
    fi

    if grep -q 'result="Passed"' "$results_path" 2>/dev/null; then
        printf 'passed'
    elif grep -q 'result="Failed"' "$results_path" 2>/dev/null; then
        printf 'failed'
    else
        printf 'unknown'
    fi
}

has_package_registration_failure() {
    local log_file="$1"

    [ -f "$log_file" ] || return 1

    if grep -Fq "[Licensing::Module] Error: 'com.unity.editor.headless' was not found." "$log_file"; then
        return 0
    fi

    grep -Fq "[Package Manager] Registered 0 packages:" "$log_file" &&
        grep -Fq "[Package Manager] The following packages were not registered because your license doesn't allow it." "$log_file"
}

has_real_licensing_failure() {
    local log_file="$1"

    [ -f "$log_file" ] || return 1

    grep -Eq "No valid Unity Editor license found|Failed to activate/update license|Entitlement-based licensing initiated but failed|License update failed" "$log_file"
}

did_tests_begin() {
    local log_file="$1"

    [ -f "$log_file" ] || return 1

    grep -Fq "Running tests for ExecutionSettings with details:" "$log_file"
}

did_test_body_begin() {
    local log_file="$1"

    [ -f "$log_file" ] || return 1

    grep -Fq "[Smoke]" "$log_file"
}

classify_failure_reason() {
    local log_file="$1"

    if [ ! -f "$log_file" ]; then
        printf 'missing-log'
        return
    fi

    if has_package_registration_failure "$log_file"; then
        printf 'package-registration-failure'
        return
    fi

    if has_real_licensing_failure "$log_file"; then
        printf 'real-licensing-failure'
        return
    fi

    if ! did_tests_begin "$log_file"; then
        printf 'startup-stall-before-tests'
        return
    fi

    if did_test_body_begin "$log_file"; then
        printf 'in-test-timeout-after-tests-begin'
        return
    fi

    printf 'startup-stall-before-tests'
}

report_failure_classification() {
    local game_id="$1"
    local log_file="$2"
    local classification

    classification="$(classify_failure_reason "$log_file")"

    case "$classification" in
        package-registration-failure)
            log_error "[$game_id] Failure classification: package/bootstrap failure. Unity batchmode started, but headless entitlement or package registration failed before tests."
            if grep -Fq "[Licensing::Module] Error: 'com.unity.editor.headless' was not found." "$log_file"; then
                log_error "[$game_id] Headless entitlement marker detected in log."
            fi
            ;;
        real-licensing-failure)
            log_error "[$game_id] Failure classification: real licensing failure. Unity reported an explicit editor-license activation/entitlement error."
            ;;
        startup-stall-before-tests)
            log_error "[$game_id] Failure classification: startup stall before tests. Unity never reached the 'Running tests for ExecutionSettings' marker."
            ;;
        in-test-timeout-after-tests-begin)
            log_error "[$game_id] Failure classification: in-test timeout after tests began. Unity started the test run and emitted smoke logs, but no final XML arrived."
            ;;
        *)
            log_error "[$game_id] Failure classification: unknown."
            ;;
    esac
}

GAME_IDS=()
split_csv_into_array "$SMOKE_GAMES" GAME_IDS

if [ ${#GAME_IDS[@]} -eq 0 ]; then
    log_error "No valid game ids found in --games."
    exit 1
fi

if [ -z "$RESULTS_DIR" ]; then
    RESULTS_DIR="$PROJECT_PATH/Logs/smoke-isolated-$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "$RESULTS_DIR"
cleanup_scene_recovery_artifacts

append_unity_launch_args
UNITY_LAUNCH_ARGS=("${UNITY_LAUNCH_ARGS_RESULT[@]}")

FAILURES=0
PASSED_GAMES=()
FAILED_GAMES=()

log "Unity Path: $UNITY_PATH"
log "Project Path: $PROJECT_PATH"
log "Test Filter: $FILTER"
log "Smoke Games: ${GAME_IDS[*]}"
if [ "$PHONE_ONLY" = "true" ]; then
    log "Smoke Mode: phone-only"
fi
log "Results Dir: $RESULTS_DIR"

for game_id in "${GAME_IDS[@]}"; do
    unity_processes=$(pgrep -af "Unity.app/Contents/MacOS/Unity" | grep -- "-projectPath $PROJECT_PATH" || true)
    if [ -n "$unity_processes" ]; then
        log_error "Another Unity instance already has this project open before starting $game_id:"
        echo "$unity_processes"
        exit 1
    fi

    rm -f "$PROJECT_PATH/Temp/UnityLockfile"

    results_path="$RESULTS_DIR/${game_id}.xml"
    log_file="$RESULTS_DIR/${game_id}.log"

    command=(
        "$UNITY_PATH"
        -batchmode
        -nographics
        "${UNITY_LAUNCH_ARGS[@]}"
        -projectPath "$PROJECT_PATH"
        -runTests
        -testPlatform PlayMode
        -testResults "$results_path"
        -testFilter "$FILTER"
        -smokeGames "$game_id"
    )

    if [ "$PHONE_ONLY" = "true" ]; then
        command+=( -smokePhoneOnly true )
    fi

    log "[$game_id] Starting isolated smoke run"
    : > "$log_file"
    set +e
    "${command[@]}" -logFile "$log_file" &
    unity_pid=$!
    wait_for_results_or_exit "$unity_pid" "$results_path" "$game_id" "$log_file"
    watcher_status=$?
    wait "$unity_pid" 2>/dev/null
    unity_exit=$?
    set -e

    result_state=$(read_test_result "$results_path")
    log "[$game_id] Unity exit=$unity_exit watcher=$watcher_status result=$result_state"
    log "[$game_id] Results: $results_path"
    log "[$game_id] Log: $log_file"

    if [ "$result_state" = "passed" ]; then
        PASSED_GAMES+=("$game_id")
        log_success "[$game_id] Passed"
    else
        FAILURES=$((FAILURES + 1))
        FAILED_GAMES+=("$game_id")
        log_error "[$game_id] Failed"
        report_failure_classification "$game_id" "$log_file"
        tail -n 40 "$log_file" 2>/dev/null || true
    fi
done

echo ""
log "Isolated smoke summary: ${#PASSED_GAMES[@]} passed, ${#FAILED_GAMES[@]} failed"
if [ ${#PASSED_GAMES[@]} -gt 0 ]; then
    log_success "Passed: ${PASSED_GAMES[*]}"
fi
if [ ${#FAILED_GAMES[@]} -gt 0 ]; then
    log_error "Failed: ${FAILED_GAMES[*]}"
fi

exit "$FAILURES"