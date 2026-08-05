#!/bin/bash

set -e

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/lib/common.sh"

print_banner "Unity Smoke PlayMode Tests"

FILTER="SmokePlayModeTests"
SMOKE_GAMES=""
SMOKE_AUTO_FINISH_GAMES=""
SMOKE_AUTO_FINISH_TIME_SCALE=""
SMOKE_LIMIT=""
RESULTS_PATH=""
AUTO_ANSWER=""
BATCH_SIZE=""
PHONE_ONLY="false"
GRAPHICS="false"
VERBOSE="false"
FAIL_FAST="false"
PHASE=""
CATEGORY=""
RUN_ID=""
PERFORMANCE_DURATION=""
PERFORMANCE_SETTLE=""
PERFORMANCE_MAX_P95_MS=""
PERFORMANCE_MAX_FRAME_MS=""
PERFORMANCE_MAX_SEVERE_HITCHES=""
PERFORMANCE_MAX_MONO_GROWTH_MB=""
RUN_RESULT_PATHS=()
CASE_TIMEOUT_SECONDS=""
IDLE_TIMEOUT_SECONDS="${SMOKE_IDLE_TIMEOUT_SECONDS:-180}"
SMOKE_PLAYER_COUNT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --games)
            SMOKE_GAMES="$2"
            shift 2
            ;;
        --limit)
            SMOKE_LIMIT="$2"
            shift 2
            ;;
        --auto-finish-games)
            SMOKE_AUTO_FINISH_GAMES="$2"
            shift 2
            ;;
        --auto-finish-time-scale)
            SMOKE_AUTO_FINISH_TIME_SCALE="$2"
            shift 2
            ;;
        --filter)
            FILTER="$2"
            shift 2
            ;;
        --results)
            RESULTS_PATH="$2"
            shift 2
            ;;
        --auto-answer)
            AUTO_ANSWER="$2"
            shift 2
            ;;
        --player-count)
            SMOKE_PLAYER_COUNT="$2"
            shift 2
            ;;
        --batch-size)
            BATCH_SIZE="$2"
            shift 2
            ;;
        --phone-only)
            PHONE_ONLY="true"
            shift
            ;;
        --graphics)
            GRAPHICS="true"
            shift
            ;;
        --verbose)
            VERBOSE="true"
            shift
            ;;
        --fail-fast)
            FAIL_FAST="true"
            shift
            ;;
        --phase)
            PHASE="$2"
            shift 2
            ;;
        --performance-duration)
            PERFORMANCE_DURATION="$2"
            shift 2
            ;;
        --performance-settle)
            PERFORMANCE_SETTLE="$2"
            shift 2
            ;;
        --max-p95-frame-ms)
            PERFORMANCE_MAX_P95_MS="$2"
            shift 2
            ;;
        --max-frame-ms)
            PERFORMANCE_MAX_FRAME_MS="$2"
            shift 2
            ;;
        --max-severe-hitches)
            PERFORMANCE_MAX_SEVERE_HITCHES="$2"
            shift 2
            ;;
        --max-mono-growth-mb)
            PERFORMANCE_MAX_MONO_GROWTH_MB="$2"
            shift 2
            ;;
        --category)
            CATEGORY="$2"
            shift 2
            ;;
        --run-id)
            RUN_ID="$2"
            shift 2
            ;;
        --case-timeout)
            CASE_TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        --idle-timeout)
            IDLE_TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        --help)
            echo "Usage: ./Scripts/runSmokeTests.sh [options]"
            echo ""
            echo "Options:"
            echo "  --games <csv>      Limit smoke tests to specific game ids"
            echo "  --auto-finish-games <csv> Run the auto-finish bot suite for specific game ids"
        echo "  --auto-finish-time-scale <x> Auto-finish speed from 1x to 20x (default: 20)"
        echo "  --player-count <n>  Override the catalog player count for the selected game"
            echo "  --limit <n>        Limit number of games after filtering"
            echo "  --batch-size <n>   Run the selected game list in sequential batches of n"
            echo "  --phone-only       Skip TV navigation paths during smoke execution"
            echo "  --graphics         Keep the graphics device enabled and require usable success screenshots"
            echo "  --verbose          Emit routine boot/lobby/teardown step tracing (noisy)"
            echo "  --fail-fast        Stop at the first per-game failure"
            echo "  --phase <name>     Run one phase: safety, load, start, lifecycle, cleanup, action, human, systems, finish, progression, all"
            echo "                     Performance is available as: --phase performance"
            echo "  --performance-duration <s> Sampling duration after the game settles (default: 10)"
            echo "  --performance-settle <s> Seconds to settle before sampling (default: 2)"
            echo "  --max-p95-frame-ms <ms> Performance gate for P95 frame time (default: 50)"
            echo "  --max-frame-ms <ms> Performance gate for maximum frame time (default: 500)"
            echo "  --max-severe-hitches <n> Allowed frames >=100ms (default: 2)"
            echo "  --max-mono-growth-mb <mb> Allowed Mono growth during sampling (default: 32)"
            echo "  --category <name>  Add a Unity test category filter"
            echo "  --run-id <id>      Stable artifact run id (default: timestamp-pid)"
            echo "  --case-timeout <s> Override per-game test timeout for debugging"
            echo "  --idle-timeout <s> Kill Unity after s seconds with no log updates (0 disables)"
            echo "  --filter <name>    Unity test filter (default: SmokePlayModeTests)"
            echo "  --results <path>   Output NUnit XML path"
            echo "  --auto-answer <y|n> Pipe a default answer to interactive prompts"
            echo "  --help             Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

filter_for_phase() {
    case "$1" in
        safety) printf '%s' "SmokePlayModeTests.AggregateSmokeTestsDoNotUseNUnitTimeoutAttributes" ;;
        load) printf '%s' "SmokePlayModeTests.LoadsGameGraphsForConfiguredGames" ;;
        start) printf '%s' "SmokePlayModeTests.StartsLocalPlayForSupportedGames" ;;
        lifecycle) printf '%s' "SmokePlayModeTests.DuplicateGameStartedKeepsTheActiveSession" ;;
        cleanup) printf '%s' "SmokePlayModeTests.ReturnsToLobbyAfterStartedGames" ;;
        action) printf '%s' "SmokePlayModeTests.ExecutesAtLeastOneGameplayActionForBotSupportedGames" ;;
        human) printf '%s' "SmokePlayModeTests.ExecutesHumanTurnThroughUIForSupportedGames" ;;
        systems) printf '%s' "SmokePlayModeTests.LoadsAvatarAndPurchaseSystems" ;;
        finish) printf '%s' "SmokePlayModeTests.AutofinishesBotMatchesForRequestedGames" ;;
        progression) printf '%s' "SmokePlayModeTests.RunsProgressionContractsForConfiguredBotGames" ;;
        performance) printf '%s' "SmokePlayModeTests.MeasuresRuntimePerformanceForConfiguredGames" ;;
        *) return 1 ;;
    esac
}

case "$PHASE" in
    ""|all) ;;
    safety|load|start|lifecycle|cleanup|action|human|systems|finish|progression|performance)
        FILTER="$(filter_for_phase "$PHASE")"
        ;;
    *) log_error "Unknown smoke phase: $PHASE"; exit 1 ;;
esac

if [ "$FILTER" = "SmokePlayModeTests.AutofinishesBotMatchesForRequestedGames" ] &&
    [ -z "$SMOKE_AUTO_FINISH_GAMES" ]; then
    log_error "The finish phase requires --auto-finish-games <csv>; refusing an empty green run."
    exit 1
fi

ISOLATE_BY_GAME="false"
ISOLATION_SOURCE="games"
case "$FILTER" in
    SmokePlayModeTests|\
    SmokePlayModeTests.LoadsGameGraphsForConfiguredGames|\
    SmokePlayModeTests.StartsLocalPlayForSupportedGames|\
    SmokePlayModeTests.DuplicateGameStartedKeepsTheActiveSession|\
    SmokePlayModeTests.ReturnsToLobbyAfterStartedGames|\
    SmokePlayModeTests.ExecutesAtLeastOneGameplayActionForBotSupportedGames|\
    SmokePlayModeTests.ExecutesHumanTurnThroughUIForSupportedGames|\
    SmokePlayModeTests.RunsProgressionContractsForConfiguredBotGames|\
    SmokePlayModeTests.MeasuresRuntimePerformanceForConfiguredGames)
        ISOLATE_BY_GAME="true"
        ;;
    SmokePlayModeTests.AutofinishesBotMatchesForRequestedGames)
        if [ -n "$SMOKE_AUTO_FINISH_GAMES" ]; then
            ISOLATE_BY_GAME="true"
            ISOLATION_SOURCE="auto-finish"
        fi
        ;;
esac

load_project_config "$PROJECT_PATH/project-config.sh" || true

if [ -z "$UNITY_VERSION" ]; then
    DETECTED_VERSION=$(detect_unity_version "$PROJECT_PATH")
    if [ -n "$DETECTED_VERSION" ]; then
        export UNITY_VERSION="$DETECTED_VERSION"
    else
        export UNITY_VERSION="6000.5.3f1"
    fi
fi

UNITY_PATH=$(find_unity_path "$UNITY_VERSION")
if [ -z "$UNITY_PATH" ]; then
    log_error "Unity $UNITY_VERSION not found."
    exit 1
fi

if [ -n "$AUTO_ANSWER" ] && [ "$AUTO_ANSWER" != "y" ] && [ "$AUTO_ANSWER" != "n" ]; then
    log_error "Invalid value for --auto-answer: $AUTO_ANSWER. Use 'y' or 'n'."
    exit 1
fi

if [ -n "$CASE_TIMEOUT_SECONDS" ] && { ! [[ "$CASE_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || [ "$CASE_TIMEOUT_SECONDS" -le 0 ]; }; then
    log_error "Invalid --case-timeout: $CASE_TIMEOUT_SECONDS. Use a positive integer."
    exit 1
fi

if [ -n "$SMOKE_PLAYER_COUNT" ] && { ! [[ "$SMOKE_PLAYER_COUNT" =~ ^[0-9]+$ ]] || [ "$SMOKE_PLAYER_COUNT" -le 0 ]; }; then
    log_error "Invalid --player-count: $SMOKE_PLAYER_COUNT. Use a positive integer."
    exit 1
fi

if [ -n "$BATCH_SIZE" ] && ! [[ "$BATCH_SIZE" =~ ^[0-9]+$ ]] ; then
    log_error "Invalid value for --batch-size: $BATCH_SIZE. Use a positive integer."
    exit 1
fi

if [ -n "$BATCH_SIZE" ] && [ "$BATCH_SIZE" -le 0 ]; then
    log_error "Invalid value for --batch-size: $BATCH_SIZE. Use a positive integer."
    exit 1
fi

if [ -n "$BATCH_SIZE" ] && [ -n "$SMOKE_GAMES" ] && [ -n "$SMOKE_AUTO_FINISH_GAMES" ]; then
    log_error "--batch-size supports either --games or --auto-finish-games, not both at the same time."
    exit 1
fi

if [ -n "$BATCH_SIZE" ] && [ -z "$SMOKE_GAMES" ] && [ -z "$SMOKE_AUTO_FINISH_GAMES" ]; then
    log_error "--batch-size requires --games or --auto-finish-games so the runner knows what to split."
    exit 1
fi

if ! [[ "$IDLE_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
    log_error "Invalid value for --idle-timeout: $IDLE_TIMEOUT_SECONDS. Use 0 or a positive integer."
    exit 1
fi

get_file_mtime() {
    local file_path="$1"

    if [ ! -f "$file_path" ]; then
        printf '0\n'
        return
    fi

    if stat -f %m "$file_path" >/dev/null 2>&1; then
        stat -f %m "$file_path"
    else
        stat -c %Y "$file_path"
    fi
}

results_file_passed() {
    local results_path="$1"

    if [ ! -f "$results_path" ]; then
        return 1
    fi

    grep -q '<test-run[^>]*result="Passed"' "$results_path"
}

watch_unity_process() {
    local unity_pid="$1"
    local log_file="$2"
    local results_path="$3"
    local idle_timeout_seconds="$4"
    local passed_marker="$5"
    local timeout_marker="$6"
    local last_mtime
    local last_progress_at
    local current_mtime
    local now_ts
    local idle_seconds

    if [ "$idle_timeout_seconds" -le 0 ]; then
        return
    fi

    last_mtime=$(get_file_mtime "$log_file")
    last_progress_at=$(date +%s)

    while kill -0 "$unity_pid" >/dev/null 2>&1; do
        sleep 5

        current_mtime=$(get_file_mtime "$log_file")
        now_ts=$(date +%s)
        if [ "$current_mtime" != "$last_mtime" ]; then
            last_mtime="$current_mtime"
            last_progress_at="$now_ts"
            continue
        fi

        idle_seconds=$((now_ts - last_progress_at))
        if [ "$idle_seconds" -lt "$idle_timeout_seconds" ]; then
            continue
        fi

        if results_file_passed "$results_path"; then
            log_warn "Unity log was idle for ${idle_seconds}s after writing passed results. Terminating hung teardown."
            : > "$passed_marker"
        else
            log_error "Unity log was idle for ${idle_seconds}s without a passed results XML. Terminating hung run."
            : > "$timeout_marker"
        fi

        kill "$unity_pid" >/dev/null 2>&1 || true
        sleep 2
        kill -9 "$unity_pid" >/dev/null 2>&1 || true
        return
    done
}

run_unity_with_followed_log() {
    local log_file="$1"
    local results_path="$2"
    shift 2
    local tail_pid
    local grep_pid
    local follow_dir
    local follow_pipe
    local unity_pid
    local watchdog_pid
    local passed_marker
    local timeout_marker
    local exit_code

    : > "$log_file"

    # Avoid Bash process substitution here: restricted macOS runners can reject
    # the /dev/fd endpoint before Unity even starts. A named pipe gives us an
    # explicit PID for both sides so teardown cannot leave tail -F behind.
    follow_dir=$(mktemp -d /tmp/boardgames-smoke-follow.XXXXXX)
    follow_pipe="$follow_dir/log.pipe"
    mkfifo "$follow_pipe"
    tail -n +1 -F "$log_file" > "$follow_pipe" &
    tail_pid=$!
    grep --line-buffered -E "\[SmokeEvent\]|Running tests|^\[Smoke\] (Starting|GameController running)|^Error |Exception:|FAILED|PASSED" < "$follow_pipe" &
    grep_pid=$!

    passed_marker=$(mktemp /tmp/boardgames-smoke-passed.XXXXXX)
    timeout_marker=$(mktemp /tmp/boardgames-smoke-timeout.XXXXXX)
    rm -f "$passed_marker" "$timeout_marker"

    if [ -n "$AUTO_ANSWER" ]; then
        (printf '%s\n' "$AUTO_ANSWER" | "$@" -logFile "$log_file") &
    else
        ("$@" -logFile "$log_file") &
    fi
    unity_pid=$!

    watch_unity_process "$unity_pid" "$log_file" "$results_path" "$IDLE_TIMEOUT_SECONDS" "$passed_marker" "$timeout_marker" &
    watchdog_pid=$!

    if wait "$unity_pid"; then
        exit_code=0
    else
        exit_code=$?
    fi

    kill "$watchdog_pid" >/dev/null 2>&1 || true
    wait "$watchdog_pid" 2>/dev/null || true

    kill "$grep_pid" >/dev/null 2>&1 || true
    kill "$tail_pid" >/dev/null 2>&1 || true
    wait "$grep_pid" 2>/dev/null || true
    wait "$tail_pid" 2>/dev/null || true
    rm -f "$follow_pipe"
    rmdir "$follow_dir" 2>/dev/null || true

    if [ -f "$passed_marker" ]; then
        exit_code=0
    elif [ -f "$timeout_marker" ]; then
        exit_code=124
    fi

    rm -f "$passed_marker" "$timeout_marker"

    return $exit_code
}

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
    IFS=',;' read -r -a raw_items <<< "$csv"
    for item in "${raw_items[@]}"; do
        item="${item#${item%%[![:space:]]*}}"
        item="${item%${item##*[![:space:]]}}"
        if [ -n "$item" ]; then
            eval "$out_var+=(\"\$item\")"
        fi
    done
}

join_array_slice() {
    local items_var="$1"
    local start_index=$2
    local slice_size=$3
    local joined=""
    local items_ref=()
    local index
    local end_index

    eval "items_ref=(\"\${${items_var}[@]}\")"
    local end_index=$((start_index + slice_size))

    if [ $end_index -gt ${#items_ref[@]} ]; then
        end_index=${#items_ref[@]}
    fi

    for ((index=start_index; index<end_index; index++)); do
        if [ -n "$joined" ]; then
            joined+=","
        fi
        joined+="${items_ref[index]}"
    done

    printf '%s' "$joined"
}

apply_limit_to_array() {
    local items_var="$1"
    local item_count

    if [ -z "$SMOKE_LIMIT" ]; then
        return
    fi

    if ! [[ "$SMOKE_LIMIT" =~ ^[0-9]+$ ]] || [ "$SMOKE_LIMIT" -le 0 ]; then
        log_error "Invalid value for --limit: $SMOKE_LIMIT. Use a positive integer."
        exit 1
    fi

    eval "item_count=\${#${items_var}[@]}"
    if [ "$item_count" -gt "$SMOKE_LIMIT" ]; then
        eval "$items_var=(\"\${${items_var}[@]:0:$SMOKE_LIMIT}\")"
    fi
}

build_batch_results_path() {
    local base_path="$1"
    local batch_index=$2
    local total_batches=$3
    local batch_tag
    batch_tag=$(printf 'batch-%02d-of-%02d' "$batch_index" "$total_batches")

    if [ -z "$base_path" ]; then
        printf '%s/batch-%02d/results.xml' "$RUN_ROOT" "$batch_index"
        return
    fi

    local extension="${base_path##*.}"
    local stem="$base_path"
    if [ "$extension" != "$base_path" ]; then
        stem="${base_path%.*}"
        printf '%s-%s.%s' "$stem" "$batch_tag" "$extension"
    else
        printf '%s-%s' "$base_path" "$batch_tag"
    fi
}

run_single_smoke_invocation() {
    local results_path="$1"
    local smoke_games="$2"
    local smoke_auto_finish_games="$3"
    local smoke_limit="$4"
    local batch_label="$5"
    local invocation_name="${6:-main}"
    local invocation_dir="$RUN_ROOT/$invocation_name"
    local log_file="$invocation_dir/unity.log"
    local events_file="$invocation_dir/events.ndjson"
    local triage_dir="$invocation_dir/triage"
    local unity_launch_args=()

    mkdir -p "$invocation_dir"
    rm -f "$events_file"
    RUN_RESULT_PATHS+=("$results_path")

    append_unity_launch_args
    unity_launch_args=("${UNITY_LAUNCH_ARGS_RESULT[@]}")

    local command=( "$UNITY_PATH" )
    if [ "$GRAPHICS" != "true" ]; then
        command+=( -batchmode -nographics )
    fi
    command+=(
        "${unity_launch_args[@]}"
        -projectPath "$PROJECT_PATH"
        -runTests
        -testPlatform PlayMode
        -testResults "$results_path"
        -testFilter "$FILTER"
        -smokeRun
        -smokeEventsPath "$events_file"
        -smokeTriageDir "$triage_dir"
    )

    if [ "$GRAPHICS" = "true" ]; then
        command+=( -smokeRequireVisualEvidence )
    fi

    if [ -n "$CATEGORY" ]; then
        command+=( -testCategory "$CATEGORY" )
    fi

    if [ -n "$smoke_games" ]; then
        command+=( -smokeGames "$smoke_games" )
    fi

    if [ -n "$smoke_auto_finish_games" ]; then
        command+=( -smokeAutoFinishGames "$smoke_auto_finish_games" )
    fi

    if [ -n "$SMOKE_AUTO_FINISH_TIME_SCALE" ]; then
        command+=( -smokeAutoFinishTimeScale "$SMOKE_AUTO_FINISH_TIME_SCALE" )
    fi

    if [ -n "$smoke_limit" ]; then
        command+=( -smokeLimit "$smoke_limit" )
    fi

    if [ -n "$SMOKE_PLAYER_COUNT" ]; then
        command+=( -smokePlayerCount "$SMOKE_PLAYER_COUNT" )
    fi

    if [ "$PHONE_ONLY" = "true" ]; then
        command+=( -smokePhoneOnly true )
    fi

    if [ "$VERBOSE" = "true" ]; then
        command+=( -smokeVerbose )
    fi

    if [ "$FAIL_FAST" = "true" ]; then
        command+=( -smokeFailFast )
    fi

    if [ -n "$CASE_TIMEOUT_SECONDS" ]; then
        command+=( -smokeCaseTimeoutSeconds "$CASE_TIMEOUT_SECONDS" )
    fi

    if [ -n "$PERFORMANCE_DURATION" ]; then
        command+=( -smokePerformanceDurationSeconds "$PERFORMANCE_DURATION" )
    fi
    if [ -n "$PERFORMANCE_SETTLE" ]; then
        command+=( -smokePerformanceSettleSeconds "$PERFORMANCE_SETTLE" )
    fi
    if [ -n "$PERFORMANCE_MAX_P95_MS" ]; then
        command+=( -smokePerformanceMaxP95FrameMs "$PERFORMANCE_MAX_P95_MS" )
    fi
    if [ -n "$PERFORMANCE_MAX_FRAME_MS" ]; then
        command+=( -smokePerformanceMaxFrameMs "$PERFORMANCE_MAX_FRAME_MS" )
    fi
    if [ -n "$PERFORMANCE_MAX_SEVERE_HITCHES" ]; then
        command+=( -smokePerformanceMaxSevereHitches "$PERFORMANCE_MAX_SEVERE_HITCHES" )
    fi
    if [ -n "$PERFORMANCE_MAX_MONO_GROWTH_MB" ]; then
        command+=( -smokePerformanceMaxMonoGrowthMb "$PERFORMANCE_MAX_MONO_GROWTH_MB" )
    fi
    if [ -n "$PERFORMANCE_MAX_GC_ALLOCATED_MB" ]; then
        command+=( -smokePerformanceMaxGcAllocatedMb "$PERFORMANCE_MAX_GC_ALLOCATED_MB" )
    fi
    if [ "$SMOKE_GC_ATTRIBUTION" = "true" ]; then
        command+=( -smokeGcAttribution )
    fi

    if [ -n "$batch_label" ]; then
        log "$batch_label"
    fi
    log "Unity Path: $UNITY_PATH"
    log "Project Path: $PROJECT_PATH"
    log "Test Filter: $FILTER"
    if [ -n "$smoke_games" ]; then
        log "Smoke Games: $smoke_games"
    fi
    if [ -n "$smoke_auto_finish_games" ]; then
        log "Smoke Auto Finish Games: $smoke_auto_finish_games"
    fi
    if [ -n "$SMOKE_AUTO_FINISH_TIME_SCALE" ]; then
        log "Smoke Auto Finish Time Scale: ${SMOKE_AUTO_FINISH_TIME_SCALE}x"
    fi
    if [ -n "$smoke_limit" ]; then
        log "Smoke Limit: $smoke_limit"
    fi
    if [ -n "$SMOKE_PLAYER_COUNT" ]; then
        log "Smoke Player Count Override: $SMOKE_PLAYER_COUNT"
    fi
    if [ "$PHONE_ONLY" = "true" ]; then
        log "Smoke Mode: phone-only"
    fi
    if [ "$GRAPHICS" = "true" ]; then
        log "Smoke Graphics: enabled (success screenshots required)"
    fi
    if [ "$IDLE_TIMEOUT_SECONDS" -gt 0 ]; then
        log "Idle Timeout: ${IDLE_TIMEOUT_SECONDS}s"
    else
        log "Idle Timeout: disabled"
    fi
    log "Results Path: $results_path"

    ensure_project_not_open_in_unity
    cleanup_scene_recovery_artifacts

    local exit_code
    if run_unity_with_followed_log "$log_file" "$results_path" "${command[@]}"; then
        exit_code=0
    else
        exit_code=$?
    fi

    if [ $exit_code -eq 0 ] && ! results_file_passed "$results_path"; then
        log_error "Unity exited successfully without a passed root <test-run>; treating the invocation as failed."
        exit_code=2
    fi

    if [ $exit_code -eq 0 ] &&
        [ "$FILTER" = "SmokePlayModeTests.AutofinishesBotMatchesForRequestedGames" ] &&
        grep -q '<test-case[^>]*result="Skipped"' "$results_path"; then
        log_error "The requested finish game has no deterministic completion driver; refusing a skipped green run."
        exit_code=2
    fi

    # Distill the multi-MB results XML / log into a ~20-line verdict. This is the
    # artifact humans and agents should read first; the raw log is a fallback only
    # needed when a summary line points at a specific failure worth digging into.
    local summary_path="$invocation_dir/summary.txt"
    local summary_json_path="$invocation_dir/summary.json"
    if [ -f "$SCRIPT_DIR/summarize_smoke.py" ]; then
        python3 "$SCRIPT_DIR/summarize_smoke.py" "$results_path" \
            --events "$events_file" --log "$log_file" --run-id "$RUN_ID" \
            --artifact-root "$RUN_ROOT" --triage-dir "$triage_dir" \
            --out "$summary_path" --json-out "$summary_json_path" --quiet 2>/dev/null || true
    fi

    if [ $exit_code -eq 0 ]; then
        log_success "Smoke PlayMode tests completed successfully"
    else
        log_error "Smoke PlayMode tests failed with exit code $exit_code"
    fi
    log "Results: $results_path"
    log "Log: $log_file"
    log "Events: $events_file"
    if [ -f "$summary_path" ]; then
        log "Summary: $summary_path"
        echo ""
        cat "$summary_path"
        echo ""
    fi

    return $exit_code
}

summarize_entire_run() {
    local args=()
    local path
    for path in "${RUN_RESULT_PATHS[@]}"; do [ -e "$path" ] && args+=("$path"); done
    for path in "$RUN_ROOT"/*/events.ndjson; do [ -e "$path" ] && args+=(--events "$path"); done
    for path in "$RUN_ROOT"/*/unity.log; do [ -e "$path" ] && args+=(--log "$path"); done

    python3 "$SCRIPT_DIR/summarize_smoke.py" "${args[@]}" \
        --run-id "$RUN_ID" --artifact-root "$RUN_ROOT" --triage-dir "$RUN_ROOT/triage" \
        --fingerprint-index "$LOGS_PATH/smoke-fingerprint-index.json" \
        --out "$RUN_ROOT/summary.txt" --json-out "$RUN_ROOT/summary.json" --quiet 2>/dev/null || true
    cp "$RUN_ROOT/summary.txt" "$LOGS_PATH/smoke-summary-latest.txt" 2>/dev/null || true
    cp "$RUN_ROOT/summary.json" "$LOGS_PATH/smoke-summary-latest.json" 2>/dev/null || true
}

build_named_results_path() {
    local base_path="$1"
    local invocation_name="$2"

    if [ -z "$base_path" ]; then
        printf '%s/%s/results.xml' "$RUN_ROOT" "$invocation_name"
        return
    fi

    local extension="${base_path##*.}"
    local stem="$base_path"
    if [ "$extension" != "$base_path" ]; then
        stem="${base_path%.*}"
        printf '%s-%s.%s' "$stem" "$invocation_name" "$extension"
    else
        printf '%s-%s' "$base_path" "$invocation_name"
    fi
}

discover_smoke_games() {
    python3 - "$PROJECT_PATH" <<'PY'
import pathlib
import re
import sys

project = pathlib.Path(sys.argv[1])
manifest_path = project / "Assets/Tests/PlayMode/Smoke/SmokeGameManifest.cs"
if not manifest_path.is_file():
    raise SystemExit(f"Fail-closed smoke manifest not found: {manifest_path}")

text = manifest_path.read_text(encoding="utf-8", errors="strict")
declaration = re.compile(
    r"(?:GraphBot|GraphScripted|GraphMissing|CodeBot|CodeMissing)\(\"([^\"]+)\"\)"
)
game_ids = declaration.findall(text)
if not game_ids:
    raise SystemExit(f"No games declared in fail-closed smoke manifest: {manifest_path}")
if len(game_ids) != len(set(game_id.casefold() for game_id in game_ids)):
    raise SystemExit(f"Duplicate game id in fail-closed smoke manifest: {manifest_path}")

print(",".join(game_ids))
PY
}

csv_contains_game() {
    local csv="$1"
    local expected="$2"
    local requested
    local normalized_requested
    local normalized_expected
    local raw_items=()

    normalized_expected=$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')
    IFS=',;' read -r -a raw_items <<< "$csv"
    for requested in "${raw_items[@]}"; do
        requested="${requested#${requested%%[![:space:]]*}}"
        requested="${requested%${requested##*[![:space:]]}}"
        normalized_requested=$(printf '%s' "$requested" | tr '[:upper:]' '[:lower:]')
        if [ "$normalized_requested" = "$normalized_expected" ]; then
            return 0
        fi
    done

    return 1
}

ensure_project_not_open_in_unity() {
    local unity_processes
    unity_processes=$(pgrep -af "Unity.app/Contents/MacOS/Unity" | grep -- "-projectPath $PROJECT_PATH" || true)

    if [ -n "$unity_processes" ]; then
        log_error "Another Unity instance already has this project open:"
        echo "$unity_processes"
        exit 1
    fi
}

LOGS_PATH="$PROJECT_PATH/Logs"
mkdir -p "$LOGS_PATH"
if [ -z "$RUN_ID" ]; then
    RUN_ID="smoke-$(date -u +%Y%m%dT%H%M%SZ)-$$"
fi
if ! [[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
    log_error "Invalid --run-id. Use letters, digits, dot, underscore, or dash."
    exit 1
fi
RUN_ROOT="$LOGS_PATH/runs/$RUN_ID"
mkdir -p "$RUN_ROOT"
UNITY_ARTIFACT_RETENTION="${SMOKE_LOG_RETENTION:-${UNITY_ARTIFACT_RETENTION:-5}}" prune_unity_artifacts "$PROJECT_PATH"

if [ -n "$BATCH_SIZE" ]; then
    if [ -n "$SMOKE_GAMES" ]; then
        split_csv_into_array "$SMOKE_GAMES" BATCH_ITEMS
        apply_limit_to_array BATCH_ITEMS
        BATCH_MODE="games"
    else
        split_csv_into_array "$SMOKE_AUTO_FINISH_GAMES" BATCH_ITEMS
        apply_limit_to_array BATCH_ITEMS
        BATCH_MODE="auto-finish"
    fi

    if [ ${#BATCH_ITEMS[@]} -eq 0 ]; then
        log_error "No games selected after applying filters for batch execution."
        exit 1
    fi

    TOTAL_BATCHES=$(( (${#BATCH_ITEMS[@]} + BATCH_SIZE - 1) / BATCH_SIZE ))
    EXIT_CODE=0

    for ((batch_zero_index=0; batch_zero_index<TOTAL_BATCHES; batch_zero_index++)); do
        batch_number=$((batch_zero_index + 1))
        start_index=$((batch_zero_index * BATCH_SIZE))
        batch_csv=$(join_array_slice BATCH_ITEMS "$start_index" "$BATCH_SIZE")
        batch_results_path=$(build_batch_results_path "$RESULTS_PATH" "$batch_number" "$TOTAL_BATCHES")
        batch_label="Batch $batch_number/$TOTAL_BATCHES"

        if [ "$BATCH_MODE" = "games" ]; then
            batch_auto_finish=""
            if [ "$FILTER" = "SmokePlayModeTests" ]; then
                # A full correctness batch must own the finish gate for the same games.
                # Passing only -smokeGames makes NUnit execute the finish test with an
                # empty selection, which is a skipped green and silently drops end-to-end
                # coverage. Keep the two selections correlated within this process.
                batch_auto_finish="$batch_csv"
            fi
            set +e
            run_single_smoke_invocation "$batch_results_path" "$batch_csv" "$batch_auto_finish" "" "$batch_label" "batch-$(printf '%02d' "$batch_number")"
        else
            set +e
            run_single_smoke_invocation "$batch_results_path" "" "$batch_csv" "" "$batch_label" "batch-$(printf '%02d' "$batch_number")"
        fi

        batch_exit=$?
        set -e
        if [ $batch_exit -ne 0 ]; then
            EXIT_CODE=$batch_exit
            if [ "$FAIL_FAST" = "true" ]; then
                break
            fi
        fi
    done

    summarize_entire_run
    exit $EXIT_CODE
fi

if [ "$ISOLATE_BY_GAME" = "true" ]; then
    # The correctness baseline owns one Unity process per game. Unity/Addressables operations are
    # only partially cancellable, so process isolation is the hard boundary after any timeout.
    if [ "$ISOLATION_SOURCE" = "auto-finish" ]; then
        split_csv_into_array "$SMOKE_AUTO_FINISH_GAMES" ISOLATED_GAME_ITEMS
    elif [ -n "$SMOKE_GAMES" ]; then
        split_csv_into_array "$SMOKE_GAMES" ISOLATED_GAME_ITEMS
    else
        DISCOVERED_SMOKE_GAMES="$(discover_smoke_games)"
        split_csv_into_array "$DISCOVERED_SMOKE_GAMES" ISOLATED_GAME_ITEMS
    fi
    apply_limit_to_array ISOLATED_GAME_ITEMS

    if [ ${#ISOLATED_GAME_ITEMS[@]} -eq 0 ]; then
        log_error "Smoke isolation did not resolve any GameGraphs ids."
        exit 1
    fi

    EXIT_CODE=0
    game_number=0
    for game_id in "${ISOLATED_GAME_ITEMS[@]}"; do
        game_number=$((game_number + 1))
        safe_game_id=$(printf '%s' "$game_id" | tr -c 'A-Za-z0-9._-' '_')
        invocation_name="game-$safe_game_id"
        game_results_path="$(build_named_results_path "$RESULTS_PATH" "$invocation_name")"
        game_smoke_games="$game_id"
        game_auto_finish=""

        if [ "$ISOLATION_SOURCE" = "auto-finish" ]; then
            game_smoke_games=""
            game_auto_finish="$game_id"
        elif [ "$FILTER" = "SmokePlayModeTests" ]; then
            # Full correctness runs own completion too. With no explicit filter, request the
            # current game and let GameGraphs.CanHaveBots decide whether a deterministic driver
            # exists. An explicit list remains an opt-in subset for focused runs.
            if [ -z "$SMOKE_AUTO_FINISH_GAMES" ] ||
                csv_contains_game "$SMOKE_AUTO_FINISH_GAMES" "$game_id"; then
                game_auto_finish="$game_id"
            fi
        fi

        set +e
        run_single_smoke_invocation \
            "$game_results_path" \
            "$game_smoke_games" \
            "$game_auto_finish" \
            "" \
            "Isolated game $game_number/${#ISOLATED_GAME_ITEMS[@]}: $game_id" \
            "$invocation_name"
        game_exit=$?
        set -e

        if [ $game_exit -ne 0 ]; then
            EXIT_CODE=$game_exit
            if [ "$FAIL_FAST" = "true" ]; then
                break
            fi
        fi
    done

    summarize_entire_run
    exit $EXIT_CODE
fi

if [ -z "$RESULTS_PATH" ]; then
    RESULTS_PATH="$RUN_ROOT/main/results.xml"
fi

set +e
run_single_smoke_invocation "$RESULTS_PATH" "$SMOKE_GAMES" "$SMOKE_AUTO_FINISH_GAMES" "$SMOKE_LIMIT" "" "main"
EXIT_CODE=$?
set -e
summarize_entire_run
exit $EXIT_CODE
